require 'test_helper'

# Ingest now defers uncached tokens to flush time and resolves them in bulk
# (EventIngestor.resolve_staged_words / Word.resolve_ids). That moves work from
# stage_event to performPendingInserts, and the invariant it can silently break
# is index completeness: every unique token of every staged event must end up
# with exactly one events_words row. A token dropped there produces an event
# that no search can find, and a token resolved to the wrong id produces a hit
# on the wrong event. Neither raises.
#
# These run in-process, so they exercise the inline write branch. The threaded
# branch is covered by event_ingest_flush_test.rb; what is under test here is
# which rows get built, not which thread writes them.
class EventIngestWordResolutionTest < ActiveSupport::TestCase
  def setup
    EventIngestor.resetCaches
  end

  def teardown
    EventIngestor.resetCaches
  end

  # (event_id, word_id) pairs actually written, as a multiset.
  def written_pairs
    Event.connection.execute(
      'select event_id, word_id from events_words order by event_id, word_id'
    ).map { |r| [r['event_id'], r['word_id']] }
  end

  def word_id(text)
    Word.where(text: text).pluck(:id)
  end

  # The core invariant: the index rows match the tokens, one row each.
  #
  # Asserted on distinctive tokens plus a no-duplicates check rather than on a
  # hand-written token list: reproducing the sanitizer's exact output here would
  # make the test a copy of the code under test.
  #
  # Event ids are read back rather than assumed: fixtures seed events, and
  # EventIngestor continues from Event.maximum(:id).
  test 'every unique token of a staged event gets exactly one index row' do
    EventIngestor.bulk_insert_size = 10
    EventIngestor.storeEvent('1.1.1.1 Jun 1 00:00:01 sshd[1]: accepted password for alice', 0)
    EventIngestor.flush_and_wait

    event_id = Event.order(:id).last.id
    pairs = written_pairs
    refute_empty pairs, 'staging one line must produce index rows'
    refute_includes pairs.map { |_e, w| w }, nil, 'no index row may carry a NULL word_id'

    %w[accepted password alice].each do |token|
      rows = pairs.select { |(_e, wid)| wid == word_id(token).first }
      assert_equal [[event_id, word_id(token).first]], rows,
        "#{token} must be indexed exactly once, against the event it came from"
    end

    event_rows = pairs.select { |(e, _w)| e == event_id }.map { |_e, w| w }
    assert_equal event_rows.uniq.size, event_rows.size,
      'a token must not be indexed twice for the same event'
  end

  # A token repeated within one line is indexed once (the tokenizer dedupes);
  # a token shared by two lines is indexed once per line.
  test 'a token repeated within a line is indexed once, across lines once per line' do
    EventIngestor.bulk_insert_size = 10
    EventIngestor.storeEvent('1.1.1.1 Jun 1 00:00:01 sshd[1]: dup dup dup token here', 0)
    EventIngestor.storeEvent('1.1.1.1 Jun 1 00:00:02 sshd[1]: dup appears again here', 1)
    EventIngestor.flush_and_wait

    dup_rows = written_pairs.count { |(_event, wid)| wid == word_id('dup').first }
    assert_equal 2, dup_rows, 'dup must be indexed once per event that contains it'
    assert_equal 1, word_id('dup').size, 'and must be one row in the words table'
  end

  # Deferral is per batch, so a token first seen in event 3 of a batch has to be
  # attributed to event 3 -- not to whichever event the batch resolves against.
  test 'tokens are attributed to the event they came from, not the batch' do
    EventIngestor.bulk_insert_size = 10
    EventIngestor.storeEvent('1.1.1.1 Jun 1 00:00:01 sshd[1]: first event marker', 0)
    EventIngestor.storeEvent('1.1.1.1 Jun 1 00:00:02 sshd[1]: second event marker', 1)
    EventIngestor.storeEvent('1.1.1.1 Jun 1 00:00:03 sshd[1]: third event marker', 2)
    EventIngestor.flush_and_wait

    ids = Event.order(:id).last(3).map(&:id)
    marker = word_id('marker').first
    assert_equal ids.sort, written_pairs.select { |(_e, w)| w == marker }.map(&:first).sort,
      'each event must own its own index row for a shared token'

    second = word_id('second').first
    assert_equal [[ids[1], second]], written_pairs.select { |(_e, w)| w == second },
      'a token unique to one event must be indexed against that event only'
  end

  # The point of deferring: a token resolved for one batch must be in the word
  # cache so the next batch never touches the words table for it. If this
  # regresses, correctness is unaffected and ingest silently slows down.
  test 'a resolved token is cached, so a later batch does not re-resolve it' do
    EventIngestor.bulk_insert_size = 1
    EventIngestor.storeEvent('1.1.1.1 Jun 1 00:00:01 sshd[1]: cached probe token', 0)
    assert EventIngestor.cached_words.key?('probe'),
      'a token resolved at flush must be added to the word cache'

    before = EventIngestor.num_cached
    EventIngestor.storeEvent('1.1.1.1 Jun 1 00:00:02 sshd[1]: cached probe token', 1)
    assert_equal before, EventIngestor.num_cached,
      'a cached token must not count as newly resolved'
    assert_equal 1, Word.where(text: 'probe').count
  end

  # num_cached drives the prune trigger in performPendingInserts. Counting
  # resolved tokens per occurrence rather than per distinct word would trip
  # prune_words far too early on a cold cache, and the adaptive TTL would then
  # shrink the cache for no reason.
  test 'num_cached counts distinct words resolved, not occurrences' do
    EventIngestor.bulk_insert_size = 10
    3.times do |i|
      EventIngestor.storeEvent("1.1.1.1 Jun 1 00:00:0#{i} sshd[1]: shared repeated token", i)
    end
    EventIngestor.flush_and_wait

    %w[shared repeated token].each do |t|
      assert EventIngestor.cached_words.key?(t), "#{t} must be cached"
      assert_equal 1, Word.where(text: t).count, "#{t} must be one row in the words table"
    end

    # Three lines x ~10 tokens, but only the tokens new to the cache count:
    # lines 2 and 3 add only their own timestamp token.
    assert_equal EventIngestor.cached_words.size, EventIngestor.num_cached,
      'num_cached must track distinct cached words, not token occurrences'
  end

  # End-to-end proof that the index survived the refactor: search is a join
  # through events_words, so a dropped or misattributed row changes results.
  # Events are identified by hunks rather than by id, since fixtures seed ids.
  test 'search still finds events by any of their tokens' do
    EventIngestor.bulk_insert_size = 10
    EventIngestor.storeEvent('1.1.1.1 Jun 1 00:00:01 sshd[1]: accepted password for alice', 0)
    EventIngestor.storeEvent('1.1.1.1 Jun 1 00:00:02 sshd[1]: failed password for bob', 1)
    EventIngestor.flush_and_wait

    range = (Time.utc(2026, 1, 1))..(Time.utc(2027, 1, 1))
    assert_equal ['1.1.1.1 Jun 1 00:00:01 sshd[1]: accepted password for alice'],
      Event.search('alice', range).pluck(:hunks)
    assert_equal ['1.1.1.1 Jun 1 00:00:02 sshd[1]: failed password for bob'],
      Event.search('bob', range).pluck(:hunks)
    assert_equal 2, Event.search('password', range).count
    assert_equal 1, Event.search('accepted password', range).count,
      'a multi-term query must intersect through the deferred index rows'
  end

  # The steady-state win, and the thing a regression to per-token lookups would
  # quietly undo: once a token is cached, a batch containing it must issue no
  # statement against the words table at all. Asserted on the SQL text rather
  # than on timing, so it fails on the mechanism, not on a threshold.
  #
  # The second line is byte-identical to the first so every one of its tokens is
  # already cached; changing the timestamp would introduce a genuinely new token
  # and the words table would correctly be hit for it.
  test 'a fully cached batch issues no words-table statements' do
    line = '1.1.1.1 Jun 1 00:00:01 sshd[1]: warm steady state token'
    EventIngestor.bulk_insert_size = 1
    EventIngestor.storeEvent(line, 0)
    EventIngestor.flush_and_wait
    assert EventIngestor.cached_words.key?('steady'),
      'the warm-up line must have populated the cache'

    statements = []
    ActiveSupport::Notifications.subscribed(
      ->(_name, _start, _finish, _id, payload) { statements << payload[:sql] },
      'sql.active_record'
    ) do
      EventIngestor.bulk_insert_size = 10
      EventIngestor.storeEvent(line, 1)
      EventIngestor.flush_and_wait
    end

    # events_words is the join table and is legitimately written by every batch;
    # what must not appear is a statement against the words table itself.
    touching_words = statements.reject { |sql| sql.include?('events_words') }
                             .grep(/\bwords\b/)
    assert_empty touching_words,
      'a cached batch must not read or write the words table'
    assert_equal 1, Word.where(text: 'steady').count
  end
end

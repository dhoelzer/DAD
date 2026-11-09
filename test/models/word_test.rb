require 'test_helper'

# Word.resolve_ids is the bulk form the ingest hot path uses: one indexed lookup
# and one multi-row INSERT per chunk, replacing one lookup plus one autocommit
# INSERT per token. Its contract is that the mapping it returns is identical to
# what per-token resolution would have produced -- same rows, same ids, same
# truncation -- because a divergence here silently changes the search index.
class WordTest < ActiveSupport::TestCase
  def setup
    Word.delete_all
  end

  test 'resolve_ids returns an id for every token, creating the missing rows' do
    existing = Word.create!(:text => 'already-here')

    ids = Word.resolve_ids(%w[already-here brand-new])

    assert_equal({ 'already-here' => existing.id, 'brand-new' => ids['brand-new'] }, ids)
    assert_equal 2, Word.count
    assert_equal [existing.id, ids['brand-new']], Word.order(:id).pluck(:id)
  end

  test 'resolve_ids collapses duplicate input into one row' do
    ids = Word.resolve_ids(%w[twice twice thrice])

    assert_equal %w[twice thrice].sort, ids.keys.sort
    assert_equal 2, Word.count
  end

  test 'resolve_ids on an empty list touches nothing' do
    assert_equal({}, Word.resolve_ids([]))
    assert_equal 0, Word.count
  end

  # The truncation rule is lossy and shared: a token longer than the column is
  # stored under its truncated form. If lookup used the untruncated text, every
  # long token would miss, insert a fresh row, and be re-inserted on each pass --
  # unbounded growth in the words table plus a search index that never matches.
  test 'long tokens are looked up and stored under the truncated form' do
    long = 'x' * 400
    truncated = Word.truncate_for_column(long)

    first = Word.resolve_ids([long])
    second = Word.resolve_ids([long])

    assert_equal 255, truncated.length
    assert truncated.end_with?('...')
    assert_equal first, second, 'a long token must resolve to the same row every time'
    assert_equal 1, Word.count, 'a long token must not be re-inserted on each pass'
    assert_equal [truncated], Word.pluck(:text)
  end

  # Chunking is what keeps the IN list and the INSERT under the adapter's
  # parameter ceiling, so the boundary between chunks must not lose or duplicate
  # tokens.
  test 'resolve_ids spans the chunk boundary without losing tokens' do
    count = Word::RESOLVE_CHUNK + 7
    tokens = Array.new(count) { |i| "chunked-#{i}" }

    ids = Word.resolve_ids(tokens)

    assert_equal count, ids.size
    assert_equal count, Word.count
    assert_equal count, tokens.map { |t| ids[t] }.uniq.size, 'every token needs its own id'
    assert_equal tokens.map { |t| ids[t] }.sort, Word.order(:id).pluck(:id).sort
  end

  # find_or_add is now the single-token form of the bulk path. The two must agree,
  # or a caller using the old API would index a token differently from ingest.
  test 'find_or_add agrees with resolve_ids' do
    bulk = Word.resolve_ids(%w[shared-token])
    single = Word.find_or_add('shared-token')

    assert_equal bulk['shared-token'], single
    assert_equal 1, Word.count
  end

  # words.text carries no unique index, so a text can already have several rows
  # (the old code could create them under concurrency). resolve_ids must pick the
  # same one the old find_by did -- the lowest id -- or ingest starts indexing
  # against a different row than the existing events_words rows do, and searches
  # for that token stop matching the older events.
  test 'resolve_ids keeps the lowest id when a text has duplicate rows' do
    older = Word.create!(:text => 'dupe')
    newer = Word.create!(:text => 'dupe')

    ids = Word.resolve_ids(['dupe'])

    assert_equal older.id, ids['dupe'], 'must match the id find_by would have returned'
    assert_equal 2, Word.count, 'resolve_ids must not add a third row'
  end

  # Guards the fallback in resolve_ids: if an adapter's RETURNING comes back
  # without ids, the rows are already committed, so the ids must be re-read
  # rather than left nil -- a nil word_id would become an index row no search
  # can ever match.
  test 'resolve_ids recovers ids when RETURNING does not provide them' do
    Word.singleton_class.send(:alias_method, :insert_all_orig, :insert_all)
    Word.define_singleton_method(:insert_all) do |rows, **kwargs|
      insert_all_orig(rows, **kwargs)
      # A Result-like stand-in for an adapter that returns no rows.
      ActiveRecord::Result.empty
    end

    ids = Word.resolve_ids(%w[needs-recovery other])

    assert_equal %w[needs-recovery other].sort, ids.keys.sort
    refute_includes ids.values, nil, 'a missing id must be recovered, not passed through'
    assert_equal 2, Word.count
  ensure
    Word.singleton_class.send(:alias_method, :insert_all, :insert_all_orig)
  end
end

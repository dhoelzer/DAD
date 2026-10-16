# One parsed syslog line, and the centre of the whole application.
#
# This is the model and the read side: the row itself, its associations, search,
# and the dashboard feed. Events are written by the ingestion pipeline
# (import_syslog.rb -> EventIngestor.storeEvent), not by the web UI -- parsing,
# tokenising, batching and the checkpoint live in EventIngestor. Each line is
# tokenised into Words and linked through the events_words join table, which is
# the search index: searching resolves terms to word ids and then scans
# events_words (see searchSQL).
class Event < ActiveRecord::Base
  # Pinned deliberately. Once events is range-partitioned on +generated+
  # (migration 20261016000001), Postgres requires the partition key in the
  # primary key, so the table's constraint becomes PRIMARY KEY (id, generated).
  # Rails reads that back and would make #id a two-element array, break
  # Event.find(id), and emit to_param values like "4-2026-07-20+10%3A00%3A00".
  #
  # The app's identity for an event has always been its id alone: ids come from a
  # single counter (EventIngestor's @nextEventID / maximum(:id) + 1), every association and
  # controller uses id by itself, and alerts_events references it alone. So the
  # model keeps id, and the extra column in the database constraint is just what
  # Postgres requires to partition.
  #
  # Trade-off: the database no longer enforces id uniqueness on its own. Ingest
  # assigns ids from one counter, so uniqueness holds; a second concurrent
  # importer would already have raced on that counter before partitioning.
  self.primary_key = 'id'

  has_and_belongs_to_many :words
  has_and_belongs_to_many :alerts
  belongs_to :system
  belongs_to :service

  # Dashboard feed size, tuned by recent_events.
  @@num_last_events = 50
  # Ceiling for that tuning. Without it, noisy exclusions keep N climbing;
  # fetching this many rows per dashboard poll is the point where the cost
  # outweighs the benefit.
  DASHBOARD_MAX_EVENTS = 1000

  # Current dashboard page size (how many recent events to fetch).
  # Read by the dashboard views; adjusted automatically by recent_events.
  def self.event_pruning_count
    @@num_last_events
  end

  # The live dashboard feed: the last N event lines, minus excluded patterns.
  #
  # Returns an Array of raw event strings (not Event records). N comes from
  # Preference.eventsDashboard and is self-tuning: if exclusions remove enough
  # rows that fewer than 50 survive, N grows 10%; if more than 70 survive, N
  # shrinks 5%. The adjusted value is persisted, so the feed converges on
  # showing roughly 50-70 lines regardless of how noisy the exclusions are.
  #
  # Patterns are matched literally: Regexp.union escapes metacharacters, so
  # "sshd.*fail" matches those seven characters, not "sshd" followed by
  # "fail". Blank and nil patterns are dropped -- Regexp.union([""]) is //,
  # which matches every line and would empty the feed for every user.
  def self.recent_events
    configured = Preference.eventsDashboard.to_i
    @@num_last_events = configured
    patterns = Exclusion.pluck(:pattern).reject { |p| p.nil? || p.strip.empty? }
    fetched = Event.last(@@num_last_events)
    events = fetched.map { |a| a.hunks }.compact
    unless patterns.empty?
      reg = Regexp.union(patterns)
      events = events.reject { |event| event.match(reg) }
    end
    # Growing only pays off when the fetch was actually truncated. If fewer
    # rows came back than were asked for, the table is that small and N would
    # otherwise climb forever on a quiet install.
    if events.count < 50 && fetched.count == configured
      @@num_last_events += configured * 0.10
    elsif events.count > 70
      @@num_last_events -= configured * 0.05
    end
    @@num_last_events = @@num_last_events.round.clamp(1, DASHBOARD_MAX_EVENTS)
    Preference.eventsDashboard(@@num_last_events) if @@num_last_events != configured
    return events
  end

  # Cheap total event count for the dashboard.
  #
  # On Postgres the figure comes from the planner statistics in pg_stat_user_tables
  # rather than COUNT(*), which is expensive on a large table. That view is
  # Postgres-specific and assumes events is partitioned as events_p*, so on any
  # other adapter -- and on an unpartitioned install, where the sum comes back
  # null -- it falls back to an exact COUNT(*). The estimate lags real inserts.
  def self.approximate_count
    connection = ActiveRecord::Base.connection
    if connection.adapter_name == "PostgreSQL"
      sql = "SELECT SUM(n_live_tup) FROM pg_stat_user_tables where relname like 'events_p%';"
      sum = connection.execute(sql).first["sum"]
      return sum.to_i unless sum.nil?
    end
    Event.count
  end

  # Show the "Events" tab only to users holding the Viewer right.
  def self.hidden?(current_user = nil)
    return true if current_user.nil?
    return true unless current_user.has_right?("Viewer")
    return false
  end
  
  # The Display rule that knows how to render this event, or nil if none matches.
  #
  # Memoised per instance: the first call runs Display.helper_for_event (a full
  # scan of Display rows), later calls are free. Views should check
  # #use_display_helper? before calling #parsed.
  def display_helper
    @display_helper = @display_helper.nil? ? Display.helper_for_event(self.hunks) : @display_helper
    @display_helper
  end
  
  # True if some Display rule matches this event, i.e. #parsed will work.
  # Guard #parsed with this to avoid rendering "BAD DISPLAY FILTER".
  def use_display_helper?
    return (self.display_helper.nil? ? false : true)
  end
  
  # This event rendered through its Display rule.
  #
  # The rule's display_script is interpreted by DisplayRule, which parses a
  # declarative field-selection spec; no Ruby from the database is evaluated
  # (RECOMMENDATIONS.md 1.2). Returns "BAD DISPLAY FILTER" when no rule matches,
  # so callers should check #use_display_helper? first.
  def parsed
    @display_helper = self.display_helper
    return "BAD DISPLAY FILTER" if @display_helper.nil?
    DisplayRule.apply(@display_helper.display_script, self.hunks)
  end
  
  # The raw line split on spaces, memoised per instance.
  # Display scripts use this to pull fields out of the line by position.
  def event_fields
    return @event_fields unless @event_fields.nil?
    @event_fields = self.hunks.split(/ +/)
    @event_fields
  end
  
  # The original, unmodified log line. Used by bin/export_logs; identical to
  # #hunks but named for the export use case.
  def reconstitute
    return self.hunks
  end
  
  # Compact one-line form for console/debug output: "host|generated|line".
  # Overrides Object#inspect, so `puts event` and `p event` show this rather than
  # the default instance dump.
  def inspect
    string = "#{self.system.display_name}|#{self.generated}|#{self.hunks}"
    return string
  end

  # Percentage of the root filesystem in use, by shelling out to df.
  # Assumes a POSIX df whose 5th column is Use%; raises if that parse fails.
  # Used by the dashboard's disk gauge.
  def self.diskUtilization
    `df -m | egrep "\s+/$"`.split(/\s+/)[4].to_i
  end
  
  # Prefix matching over words.text: find every indexed word that starts with
  # the search term. The exact predicate is `text like 'term%' escape '\'` --
  # the ESCAPE pins % and _ to literals so a term like 'foo_bar' cannot match
  # 'fooXbar'. How the lookup is narrowed to stay index-driven differs per
  # adapter, because the two adapters order text differently.
  #
  # SQLite's default collation is BINARY, so [term, term + U+10FFFF) is a sound
  # range holding exactly the strings that start with term, and index_words_on_text
  # serves it. The upper bound is not decoration: without it SQLite estimates the
  # subquery at half the table and re-plans the outer join to drive from
  # events_words through the generated index, scanning every join row in the time
  # window instead of only the matched words'.
  #
  # Postgres cannot use that range. Its collation is whatever the cluster was
  # initialised with -- en_US.UTF-8 for postgres:17 and for provision.sh -- and
  # under glibc's en_US.UTF-8 strcoll sorts U+10FFFF *before* ASCII letters, so
  # the bound falls below every longer word and prefix search silently returns
  # nothing. Measured on 280k words: term 'sshd' matched 60000 words by LIKE and
  # 0 by that range.
  #
  # Nor can the bound be repaired. en_US.UTF-8 gives trailing punctuation no
  # primary weight, so 'foo-' and 'foo' share a primary weight sequence and the
  # strings sorting above 'foo-' are unbounded. Exhaustively checked over the 94
  # printable ASCII characters the tokenizer can emit: incrementing the last
  # character is an unsound bound for 35 of them, including every one of
  # - . / : @ * _ that can end a word.
  #
  # So Postgres matches on the LIKE alone, served by index_words_on_text_pattern
  # (varchar_pattern_ops), which indexes raw bytes and is therefore collation-blind.
  WORD_IDS_BYTEWISE = "select id from words where text >= ? and text < ? and text like ? escape '\\'".freeze
  WORD_IDS_LIKE = "select id from words where text like ? escape '\\'".freeze

  # U+10FFFF is the highest Unicode code point, so term + PREFIX_UPPER bounds
  # every string starting with term -- but only where text is ordered byte-wise.
  # See WORD_IDS_BYTEWISE before using it anywhere else.
  PREFIX_UPPER = "\u{10FFFF}".freeze

  # The words lookup for one term, as [sql, binds].
  #
  # Returned per term rather than as a constant because the placeholder count
  # differs by adapter: keeping the fragment and its binds together is what stops
  # the two from drifting apart.
  def self.word_lookup(term)
    pattern = "#{sanitize_sql_like(term)}%"
    if connection.adapter_name == 'SQLite'
      [WORD_IDS_BYTEWISE, [term, term + PREFIX_UPPER, pattern]]
    else
      [WORD_IDS_LIKE, [pattern]]
    end
  end
  private_class_method :word_lookup

  # Returns [sql, binds]. Returns the ids of events whose words cover every one
  # of the search terms.
  #
  # This is relational division: the derived table pairs each matching word with
  # the term that matched it, and HAVING count(distinct term_no) = n keeps only
  # events that saw all n terms. Counting distinct matching word_ids instead
  # (the original behaviour) breaks whenever one term is a prefix of another word
  # on the same event ("test" also matches "testservice"), which silently hides
  # events from search results.
  #
  # Each term's word set is resolved exactly once. It used to be resolved twice
  # -- once to restrict events_words and again inside HAVING, as
  # `max(case when word_id in (<same subquery>) then 1 else 0 end)` per term --
  # which made the planner scan words 2n times. Measured on 280k words / 6M
  # events_words rows with a term matching 60k words: 534ms -> 394ms for one
  # term, 1386ms -> 1067ms for three. It also halves the placeholder count,
  # which matters because a search over a busy system already runs close to
  # PostgreSQL's 65535-parameter statement limit.
  #
  # The term -> word_id lookup still happens in a subquery rather than by joining
  # words into the scan: joining words directly forces events_words to be read
  # through the generated index and then re-filtered, which is a full scan of
  # every join row in the time window. Restricting on word_id instead lets the
  # database use index_events_words_on_word_id_and_generated_and_event_id as a
  # covering index and read only the rows for the matched words.
  #
  # The query string is built only from placeholders: `search_terms` arrives
  # straight from params[:search_terms], so nothing user-supplied may be
  # interpolated into it.
  def self.searchSQL(starting_time, ending_time, terms)
    lookups = terms.map { |term| word_lookup(term) }
    derived = lookups.each_with_index.map do |(lookup, _binds), index|
      "select id as word_id, #{index + 1} as term_no from (#{lookup}) terms#{index + 1}"
    end.join(' union all ')

    sql = "select events_words.event_id from events_words " +
      "join (#{derived}) terms on terms.word_id = events_words.word_id " +
      "where (events_words.generated between ? and ?) " +
      "group by events_words.event_id having (count(distinct terms.term_no)) = ?"

    # binds follow placeholder order: the derived table's subqueries, then the
    # time range, then the expected term count.
    binds = lookups.flat_map { |_lookup, term_binds| term_binds }
    binds << starting_time.to_fs(:db) << ending_time.to_fs(:db)
    binds << terms.count
    [sql, binds]
  end

  # Returns a relation over the matching events. The search SQL is embedded as a
  # subquery rather than run first and its ids interpolated into an `id in (?)`
  # list: that round trip materialised every matching id (a search over a busy
  # system can match hundreds of thousands of events) and blew past PostgreSQL's
  # 65535-parameter statement limit.
  # Searches events whose line contains every whitespace-separated term in
  # +search_string+, from +starting_time+ up to now.
  #
  # Returns an ActiveRecord::Relation ordered oldest-first, so callers may chain
  # further scopes; #count gives the number of matches (capped at +limit+) and
  # #to_a gives the page. Returns [] for an empty/whitespace-only query.
  # Terms are matched as literal *prefixes* of indexed words, case-insensitively
  # (input is downcased); +offset+ / +limit+ page the result.
  # Used by EventsController#search for both the relative and absolute forms:
  # the only difference between them is the window, so there is one method.
  #
  # +time_range+ is a Range of Times, e.g. (Time.now - 1.hour)..Time.now for the
  # relative form and starttime..endtime for the absolute one. The default is the
  # last hour, matching the relative form's usual call.
  def self.search(search_string, time_range=(Time.now - 1.hour)..Time.now, offset=0, limit=100)
    terms = search_string.downcase.split(/\s+/)
    return [] if terms.empty?
    # Guard rather than let #begin raise: a feature step used to pass 0 here,
    # which the old two-argument form bound as the string '0' and so matched
    # every event. The test passed for a reason that had nothing to do with the
    # feature it described.
    unless time_range.respond_to?(:begin) && time_range.respond_to?(:end)
      raise ArgumentError, "time_range must be a Range of Times, got #{time_range.inspect}"
    end
    matching_events(terms, time_range.begin, time_range.end, offset, limit)
  end

  # Builds the relation for a set of already-split +terms+ over a time window.
  # Backend for #search; internal.
  def self.matching_events(terms, starting_time, ending_time, offset, limit)
    sql, binds = searchSQL(starting_time, ending_time, terms)
    scoped = sanitize_sql_array(["id in (#{sql})", *binds])
    Event.where(scoped).order(generated: :asc).limit(limit).offset(offset)
  end
  private_class_method :matching_events
end

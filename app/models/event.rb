# One parsed syslog line, and the centre of the whole application.
#
# Events are written by the ingestion pipeline (import_syslog.rb -> storeEvent),
# not by the web UI. Each line is tokenised into Words and linked through the
# events_words join table, which is the search index: searching resolves terms to
# word ids and then scans events_words (see searchSQL).
#
# Writes are batched and performed on background threads, so class-level state
# below is process-global and the class is intended to be driven by a single
# long-running importer process.
class Event < ActiveRecord::Base
  has_and_belongs_to_many :words
  has_and_belongs_to_many :alerts
  belongs_to :system
  belongs_to :service

  # Rows per INSERT batch. Starts at 1 in dev/test (so tests can observe writes
  # immediately) and 2000 in production; performPendingInserts retunes it to
  # track throughput.
  @bulk_insert_size=((Rails.env.development? || Rails.env.test?) ? 1 : 2000)
  # Memo of token -> {id:, last:} so repeated words skip the DB during ingest.
  # Pruned by prune_words once it exceeds CACHESIZE entries.
  @@cached_words = Hash.new
  # Dashboard feed size, tuned by recent_events.
  @@num_last_events = 50
  # Ceiling for that tuning. Without it, noisy exclusions keep N climbing;
  # fetching this many rows per dashboard poll is the point where the cost
  # outweighs the benefit.
  DASHBOARD_MAX_EVENTS = 1000
  @added = 0
  @cache_hits = 0
  @@num_cached = 0
  # Lines dropped because no timestamp format matched. Counted rather
  # than silently returned, so ingestion loss is observable.
  @@timestamp_parse_failures = 0
  # Word-cache size that triggers a prune, and the current TTL in seconds.
  # prune_words grows/shrinks the TTL to keep the cache near CACHESIZE.
  CACHESIZE=100000
  @@cachelifetime=320
  # Ingest checkpoint state, set by begin_ingest for the file being read.
  # @@ingest_position is the byte offset just staged; @@ingest_checkpoint is the
  # offset whose rows are known durable. They differ by whatever is staged or in
  # flight, and only the checkpoint may be persisted.
  @@checkpoint_writer = nil
  @@ingest_position = 0
  @@ingest_checkpoint = 0
  # Guards @@insertThreads and the checkpoint sidecar: writer threads advance it
  # concurrently with the main thread.
  @@checkpoint_mutex = Mutex.new
  # Background INSERT threads not yet joined.
  @@insertThreads = Array.new
  @inserted_last_run = 100
  # Next primary key to assign. Events get explicit ids so that events_words
  # rows can be staged before the event itself is inserted; this counter must
  # stay ahead of anything already in the table (see storeEvent).
  @@nextEventID = -1
  # Staged rows awaiting the next flush.
  @@pendingEventValues = Array.new
  @@system_cache = Hash.new
  @@service_cache = Hash.new
  @@events_words = Array.new
  @@start_time = Time.now
  @display_helper = nil       # Using lazy initialization but still using instance vars so that we
  @event_fields = nil         # instantiate lazily but still only do one SQL query per event
  # Year assumed for syslog lines that carry a timestamp without a year
  # (the classic "Jun  1 12:00:00" form). Refreshed on each flush so a long
  # ingest run does not misdate lines across a year boundary.
  @@current_year = Time.new.year
  
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
  
  # The original, unmodified log line. Used by export_logs.rb; identical to
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
  
  # Restarts the throughput clock used to compute events/sec in
  # performPendingInserts. Call after a burst that should not count, e.g. at the
  # start of an import_syslog.rb pass.
  def self.resetStats
    @@start_time = Time.now
  end

  # The class-level caches key on database row IDs. When the database is rolled
  # back or truncated (test suites, or a long-lived process pointed at a fresh
  # DB), those IDs dangle and later inserts/searches silently reference rows
  # that no longer exist. Drop all of it and re-derive from the current DB.
  def self.resetCaches
    @@cached_words = Hash.new
    @@num_cached = 0
    @@nextEventID = -1
    @@pendingEventValues = Array.new
    @@system_cache = Hash.new
    @@service_cache = Hash.new
    @@events_words = Array.new
    @@insertThreads.each { |batch| batch.thread.join }
    @@insertThreads = Array.new
    @@checkpoint_writer = nil
    @@ingest_position = 0
    @@ingest_checkpoint = 0
    @@current_year = Time.new.year
    @@timestamp_parse_failures = 0
    # @bulk_insert_size grows adaptively with throughput; without a reset, a
    # single storeEvent can sit in the pending set indefinitely.
    @bulk_insert_size = ((Rails.env.development? || Rails.env.test?) ? 1 : 2000)
    @inserted_last_run = 100
    @added = 0
    @cache_hits = 0
    resetStats
  end
  
  # U+10FFFF is the highest Unicode code point, so [term, term + PREFIX_UPPER)
  # is a B-tree-friendly range that contains every string starting with term.
  # LIKE 'term%' cannot drive an index scan, which is why the lookup is written
  # as a range. The range is only a narrowing filter: under a collating sequence
  # that ignores punctuation (PostgreSQL's en_US.UTF-8, say) it can also admit
  # strings that do not start with term -- 'a-b' falls inside the range for
  # 'ab'. The trailing LIKE with an explicit ESCAPE is what pins the semantics
  # down to a literal prefix on every adapter.
  PREFIX_UPPER = "\u{10FFFF}".freeze

  WORD_IDS = "select id from words where text >= ? and text < ? and text like ? escape '\\'".freeze

  # Returns [sql, binds]. Counts, per event, how many of the search terms match
  # at least one of that event's words, and keeps events where every term
  # matched. Counting distinct matching word_ids instead (the previous
  # behaviour) breaks whenever one term is a prefix of another word on the same
  # event ("test" also matches "testservice"), which silently hides events from
  # search results.
  #
  # The term -> word_id lookup happens in a subquery rather than by joining
  # words into the scan: the join forces events_words to be read through the
  # generated index and then re-filtered, which is a full scan of every join row
  # in the time window. Restricting on word_id instead lets the database use
  # index_events_words_on_word_id_and_generated_and_event_id as a covering
  # index and read only the rows for the matched words.
  #
  # The query string is built only from placeholders: `search_terms` arrives
  # straight from params[:search_terms], so nothing user-supplied may be
  # interpolated into it.
  def self.searchSQL(starting_time, ending_time, terms)
    matched_terms = terms.map { "max(case when events_words.word_id in (#{WORD_IDS}) then 1 else 0 end)" }.join(' + ')
    sql = "select event_id from events_words " +
      "where events_words.word_id in (#{terms.map { WORD_IDS }.join(' union all ')}) " +
      "and (events_words.generated between ? and ?) " +
      "group by event_id having (#{matched_terms}) = ?"

    binds = []
    # binds must follow placeholder order: WHERE subqueries, then the range,
    # then the HAVING subqueries, then the expected term count.
    terms.each { |term| binds.concat(word_binds(term)) }
    binds << starting_time.to_fs(:db) << ending_time.to_fs(:db)
    terms.each { |term| binds.concat(word_binds(term)) }
    binds << terms.count
    [sql, binds]
  end

  # Range bounds plus the escaped LIKE pattern for one search term.
  def self.word_binds(term)
    [
      term,
      term + PREFIX_UPPER,
      "#{sanitize_sql_like(term)}%",
    ]
  end
  private_class_method :word_binds

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
  # Used by EventsController#search for the relative-time-range form.
  def self.search(search_string, starting_time=(Time.now - 1.hour), offset=0, limit=100)
    terms = search_string.downcase.split(/\s+/)
    return [] if terms.empty?
    matching_events(terms, starting_time, Time.now, offset, limit)
  end

  # Same as #search but over an explicit [starting_time, ending_time] window.
  # Used by EventsController#search when the absolute-time form is submitted.
  def self.search_period(search_string, starting_time, ending_time, offset=0, limit=100)
    terms = search_string.downcase.split(/\s+/)
    return [] if terms.empty?
    matching_events(terms, starting_time, ending_time, offset, limit)
  end

  # Builds the relation for a set of already-split +terms+ over a time window.
  # Shared by #search and #search_period; internal.
  def self.matching_events(terms, starting_time, ending_time, offset, limit)
    sql, binds = searchSQL(starting_time, ending_time, terms)
    scoped = sanitize_sql_array(["id in (#{sql})", *binds])
    Event.where(scoped).order(generated: :asc).limit(limit).offset(offset)
  end
  private_class_method :matching_events

  # Recognizes the timestamp that follows the host token and reports how many
  # whitespace-separated tokens it consumed, so the caller can locate the
  # service name without assuming a fixed offset.
  #
  # Returns [DateTime, token_count], or [nil, 0] when nothing parses. Formats,
  # tried in order:
  #   1. ISO 8601 / RFC 3339 ("2026-06-01T12:34:56.123Z", "...+02:00")
  #      -- 1 token, or 2 when the sanitizer split a "+HH:MM" offset off it
  #   2. ISO date and time as separate tokens ("2026-06-01 12:34:56")  -- 2 tokens
  #   3. RFC 3164 with an explicit year ("Jun 01 2015 12:00:00")       -- 4 tokens
  #   4. Classic RFC 3164, no year ("Jun  1 12:00:00")                 -- 3 tokens
  #
  # Format 1 used to require exactly three fractional digits and a literal Z,
  # which silently mis-parsed the RFC 3339 output rsyslog emits by default.
  # Format 3 used to be gated on a hard-coded 2015-2019 window; outside it,
  # dated lines fell through to format 4 and lost their time of day.
  #
  # +year+ fills in the missing year for format 4. Offsets are normalized to
  # UTC because the value is stored with to_fs(:db), which drops the offset.
  def self.parse_timestamp(tokens, year)
    return [nil, 0] if tokens.nil? || tokens.empty?

    if tokens[0] =~ /\A\d{4}-\d{2}-\d{2}t[\d:.]+(?:z|[+-]\d{2}:?\d{2})\z/
      begin
        return [DateTime.parse(tokens[0]).new_offset(0), 1]
      rescue ArgumentError
        return [nil, 0]
      end
    end

    if tokens[0] =~ /\A\d{4}-\d{2}-\d{2}t[\d:.]+\z/
      # storeEvent's sanitizer replaces '+' with a space, so an RFC 3339
      # '+HH:MM' offset arrives as a second token; '-HH:MM' stays attached.
      iso = tokens[0]
      consumed = 1
      if tokens[1] =~ /\A\d{2}:?\d{2}\z/
        iso = "#{iso}+#{tokens[1]}"
        consumed = 2
      end
      begin
        return [DateTime.parse(iso).new_offset(0), consumed]
      rescue ArgumentError
        return [nil, 0]
      end
    end

    if tokens.size >= 2 && tokens[0] =~ /\A\d{4}-\d{2}-\d{2}\z/ && tokens[1] =~ /\A\d{2}:\d{2}(?::\d{2})?(?:[.,]\d+)?\z/
      begin
        return [DateTime.parse("#{tokens[0..1].join(' ')} GMT"), 2]
      rescue ArgumentError
        return [nil, 0]
      end
    end

    if tokens.size >= 4 && tokens[3] =~ /\A\d{2}:\d{2}:\d{2}\z/ && tokens[2] =~ /\A\d{4}\z/
      begin
        return [DateTime.parse("#{tokens[0..3].join(' ')} GMT"), 4]
      rescue ArgumentError
        return [nil, 0]
      end
    end

    if tokens.size >= 3 && tokens[2] =~ /\A\d{2}:\d{2}:\d{2}\z/
      begin
        return [DateTime.parse("#{tokens[0..2].join(' ')} #{year.to_i} GMT"), 3]
      rescue ArgumentError
        return [nil, 0]
      end
    end

    [nil, 0]
  end

  # Parses one raw log line and stages it for insertion.
  #
  # This is the ingestion entry point, called once per line by import_syslog.rb.
  # It does not return a meaningful value and silently drops lines it cannot
  # parse (too few fields, unparseable timestamp, empty service) -- that is
  # deliberate: a live syslog feed must never stop on a malformed line.
  #
  # Steps: normalise the text, detect the timestamp format (see parse_timestamp),
  # resolve the System and Service, map each unique token to a word id, then
  # append to the pending batches. Nothing is written until the batch reaches
  # @bulk_insert_size, at which point performPendingInserts flushes it.
  #
  # +eventString+ must begin with the originating host, followed by the timestamp
  # and service, e.g. "host.example.com Jun  1 12:00:00 sshd[123]: ...".
  def self.storeEvent(eventString, position = nil)
    # Staging is all-or-nothing. The word loop appends to @@events_words before
    # the event row is appended to @@pendingEventValues, so a raise part-way
    # through leaves index rows for an event id that never gets an events row
    # (search hits that 404), and @@nextEventID is not advanced, so the next
    # line reuses the id and dies on a UNIQUE violation. The importer now skips
    # bad lines instead of exiting, which makes a partially staged line a
    # permanent corruption rather than a one-off crash.
    words_staged = @@events_words.count
    events_staged = @@pendingEventValues.count
    begin
      stage_event(eventString, position)
    rescue StandardError
      # A flush inside stage_event resets both arrays, so the captured counts
      # can be past the end; slice! then no-ops, which is the correct outcome
      # (those rows are already handed off, not partial).
      @@events_words.slice!(words_staged..-1)
      @@pendingEventValues.slice!(events_staged..-1)
      raise
    end
  end

  # Parses one line and appends it to the pending batches. Internal: the body of
  # storeEvent, split out so storeEvent can roll staging back on failure.
  def self.stage_event(eventString, position)
    # This next line is to seek and destroy invalid UTF-8 byte sequences.  They seem to show up in some
    # logs, sometimes in URLs.
    eventString = eventString.encode('UTF-8', :invalid => :replace)
    eventString.tr!("\r\n", "")
    hunks = eventString.dup
    eventString.downcase!
    eventString.gsub!(/([^a-zA-Z0-9 \-_:@\*\/.])/," " )
    split_text = eventString.split(/\s+/)
    if split_text.count < 5 then
      Rails.logger.warn "Invalid for syslog format: Too few fields -> #{eventString}"
      return
    end
    # The service follows the timestamp, so its position is whatever the
    # timestamp turned out to consume; +1 skips the host token.
    timestamp, consumed = parse_timestamp(split_text[1..-1], @@current_year)
    if timestamp.nil? then
      @@timestamp_parse_failures += 1
      return
    end
    service_offset = 1 + consumed
    txtsystem = split_text[0]
    if @@system_cache.has_key?(txtsystem) then
      system = @@system_cache[txtsystem]
    else
      system = System.find_or_add(txtsystem)
      @@system_cache[txtsystem] = system
    end
    txtservice = split_text[service_offset]
    if txtservice.nil? then
      Rails.logger.warn "Service empty: #{eventString}"
      return
    end
    txtservice = txtservice.tr("^a-zA-Z\-_/","")
    if @@service_cache.has_key?(txtservice) then
      service = @@service_cache[txtservice]
    else
      service = Service.find_or_add(txtservice)
      @@service_cache[txtservice] = service
    end

    # Is this the first event inserted? If so, figure out what the maximum ID is right now.
    # Events are assigned ids explicitly so events_words rows can be staged ahead of
    # the event row; the counter must not collide with existing rows.
    if @@nextEventID == -1 then
      # maximum(:id) is MAX(id) over the primary key. The previous Event.all.count
      # was a full table scan on every importer restart, on a table sized in the
      # hundreds of millions.
      @@nextEventID = (Event.maximum(:id) || 0) + 1
    end

    # Precalculate some needed values and perform necessary conversions.
    timestamp_s = timestamp.to_fs(:db)
    time_now = Time.now

    # Take all of the words, make them unique and make sure that they are in the DB. Look up their IDs.
    split_text.to_set.to_a.each do |word| 
      if @@cached_words.has_key?(word) then
        @@cached_words[word][:last] = time_now
        @cache_hits += 1
        dbWord = @@cached_words[word][:id]
      else
        dbWord = Word.find_or_add(word)
        @@num_cached += 1
        @@cached_words[word] = {:id => dbWord, :last => time_now}
      end
      @@events_words << {:event_id => @@nextEventID, :word_id => dbWord, :generated => timestamp_s}
    end
    # Values are staged as-is and bound as parameters at flush time, so log text
    # (which is attacker-controlled) never becomes part of the SQL string.
    @@pendingEventValues << {:id => @@nextEventID, :system_id => system.id, :service_id => service.id,
                             :generated => timestamp_s, :stored => time_now.to_fs(:db), :hunks => hunks}

    @@nextEventID += 1
    # Set before the flush so the batch being handed off carries this line's
    # offset. Lines the parser skipped leave it behind; the next staged line
    # covers them, since offsets only move forward.
    @@ingest_position = position if position
    self.performPendingInserts if @@pendingEventValues.count >= @bulk_insert_size
  end

  # Builds a single multi-row INSERT plus its bind parameters. Only the table
  # and column names (all literals from this file) reach the SQL text; every
  # value is bound. SQLite caps host parameters far above the largest batch
  # this produces, so batching is preserved.
  # Binds are plain values: Rails 7.1 removed the legacy [type, value] pair form
  # that exec_query accepted, and type_cast now raises "can't cast Array" on it.
  def self.insertStatement(table, columns, rows)
    row_placeholder = "(#{(['?'] * columns.size).join(', ')})"
    sql = "INSERT INTO #{table} (#{columns.join(', ')}) VALUES " +
      Array.new(rows.size) { row_placeholder }.join(', ')
    binds = rows.flat_map { |row| columns.map { |c| row[c] } }
    [sql, binds]
  end

  # Batches allowed in flight at once.
  #
  # One still keeps a batch writing while the main thread parses the next one,
  # which is the point of the threads, without ever holding two write
  # transactions at the same time. The old limit of 5 meant 5 insert threads plus
  # the main thread could ask for 6 connections from a pool of 5, so a flush
  # would block on the pool timeout instead of writing; and two concurrent
  # writers are not available on the SQLite database development and the test
  # suite use, which fails them with SQLite3::BusyException.
  MAX_INSERT_THREADS = 1

  # Writes the staged event and events_words batches, then resets them.
  #
  # Called automatically by storeEvent once a batch is full, and explicitly by
  # import_syslog.rb at the end of each pass (and on Ctrl-C) so nothing is left
  # in memory. Outside the test environment the two INSERTs run on a background
  # thread so ingestion is not blocked by the write; at most
  # MAX_INSERT_THREADS batches are in flight, and a batch that failed on its
  # thread raises here rather than being dropped.
  #
  # After each flush it retunes @bulk_insert_size (+20 when throughput improved,
  # -20 down to a floor of 20 when it fell) and logs the rate as a Statistic.

  # Writes one staged batch. Both INSERTs share a transaction: events_words is
  # written first, so a crash between the two left index rows pointing at
  # events that do not exist -- search hits that 404.
  #
  # Takes the rows as arguments instead of reading the class-level queues, so a
  # caller can hand a batch to a thread without the queues changing underneath
  # it. Internal: the only writer of a staged batch.
  def self.write_batch(ew_sql, ew_binds, ev_sql, ev_binds)
    ActiveRecord::Base.transaction do
      connection = ActiveRecord::Base.connection
      connection.exec_query ew_sql, "SQL", ew_binds
      connection.exec_query ev_sql, "SQL", ev_binds
    end
  end
  private_class_method :write_batch
  private_class_method :stage_event

  # Joins every outstanding INSERT thread and re-raises the first failure any
  # of them recorded.
  #
  # A thread that died holding a batch means those events are gone, so the
  # failure is surfaced rather than swallowed: the importer stops with its logs
  # still in LogsToProcess instead of carrying on as if the write succeeded.
  # Silent loss is the worse outcome for a tool whose whole job is to keep
  # these lines.
  def self.join_insert_threads
    pending = @@checkpoint_mutex.synchronize { @@insertThreads.dup }
    failures = pending.map do |batch|
      batch.thread.join
      batch.thread.value
    end.compact
    @@checkpoint_mutex.synchronize { @@insertThreads = [] }
    raise failures.first unless failures.empty?
  end

  # Starts a checkpointed ingest pass over one file.
  #
  # +resume_offset+ is where a previous run left off, 0 for a fresh file.
  # +checkpoint_writer+ is handed the byte offset each time its rows become
  # durable. It is a block rather than a call into LogQueue because lib/ is not
  # autoloaded, so the model must not name that constant.
  def self.begin_ingest(resume_offset, &checkpoint_writer)
    # Drain the previous file first. Its batches still carry its byte offsets,
    # and checkpointing those into the new file's sidecar would skip rows.
    flush_and_wait
    @@checkpoint_writer = checkpoint_writer
    @@ingest_position = resume_offset
  end

  # Records the durable checkpoint for every finished batch at the head of the
  # queue, in order.
  #
  # Called by the writer threads themselves, not only by the main thread: if
  # only the main thread did it, a process killed while a batch was in flight
  # could commit rows without ever recording them, and the next run would
  # re-insert them. Measured as exactly that failure -- a 6-line file that died
  # with one batch in flight ended up with lines 1 and 2 stored twice.
  #
  # Only the head can be released. With two batches in flight, recording the
  # later offset while the earlier one is still unwritten would tell a
  # recovering run to skip rows that were never committed.
  #
  # The mutex covers both the queue mutation and the sidecar write, so two
  # threads cannot interleave and persist an offset that the other has not
  # earned yet.
  def self.advance_checkpoint!
    @@checkpoint_mutex.synchronize do
      while (entry = @@insertThreads.first)
        break unless entry.finished
        @@insertThreads.shift
        @@ingest_checkpoint = entry.position
        @@checkpoint_writer&.call(entry.position)
      end
    end
  end

  # One staged batch on its way to the database.
  #
  # +position+ is the byte offset of the last line the batch covers; +finished+
  # is set by the thread once its rows are committed, which is what makes the
  # batch eligible to advance the checkpoint.
  IngestBatch = Struct.new(:thread, :position, :finished)

  def self.performPendingInserts
    # Surface a batch that already failed before staging any more work.
    join_insert_threads if @@insertThreads.any? { |b| !b.thread.alive? }

    return if @@pendingEventValues.count < 1

    if @@insertThreads.count >= MAX_INSERT_THREADS then
      Rails.logger.debug "Joining previous inserts."
      join_insert_threads
    end
    ew_sql, ew_binds = insertStatement('events_words', [:event_id, :word_id, :generated], @@events_words)
    ev_sql, ev_binds = insertStatement('events', [:id, :system_id, :service_id, :generated, :stored, :hunks], @@pendingEventValues)

    # Measured before the queues are cleared: the throughput figure below needs
    # the size of the batch just handed off. Reading @@pendingEventValues after
    # the reset yields 0, which zeroed every logged rate and let
    # @bulk_insert_size climb without bound.
    batch_count = @@pendingEventValues.count

    # Cleared as soon as the rows are captured into the statements, before the
    # stats bookkeeping below. Statistic.logEventsPerSecond writes to the same
    # database and can fail; when it raised, the rows it had *already* handed to
    # a writer thread were still staged, so the next flush inserted them a
    # second time under the same explicit ids and died on
    # UNIQUE constraint failed: events.id. Reproduced on SQLite under a
    # crash-then-reclaim run.
    @@pendingEventValues = Array.new
    @@events_words = Array.new

    if Rails.env.test?
      # Cucumber runs DatabaseCleaner inside an open transaction and SQLite
      # permits a single writer, so a second connection deadlocks the suite.
      # Inline keeps the same write_batch path, just without the thread.
      write_batch(ew_sql, ew_binds, ev_sql, ev_binds)
      # Inline: the rows are durable the moment write_batch returns.
      @@checkpoint_mutex.synchronize do
        @@ingest_checkpoint = @@ingest_position
        @@checkpoint_writer&.call(@@ingest_position)
      end
    else
      # The batch reaches the thread by value, and the queues are cleared only
      # after the handoff, so the thread owns its own rows and no later reset
      # can pull them out from under it.
      batch = IngestBatch.new(nil, @@ingest_position, false)
      # Queued before the thread starts. If the write finished first, the thread
      # would call advance_checkpoint! against a queue that does not yet hold
      # this batch and its checkpoint would never be released.
      @@checkpoint_mutex.synchronize { @@insertThreads << batch }
      batch.thread = Thread.new(ew_sql, ew_binds, ev_sql, ev_binds, batch) do |ew_sql, ew_binds, ev_sql, ev_binds, batch|
        begin
          write_batch(ew_sql, ew_binds, ev_sql, ev_binds)
          # Rows are durable: this batch may now release the checkpoint, but
          # only if every earlier batch has already finished.
          batch.finished = true
          Event.advance_checkpoint!
          nil
        rescue Exception => e
          # Thread#value returns a raised exception rather than re-raising it;
          # join_insert_threads turns that back into a real failure. A failed
          # batch never advances the checkpoint, so its lines get re-read.
          e
        end
      end
    end
    #puts "\t\t-->> Flushed #{batch_count} events. <<--"
    elapsed_time = (Time.now - @@start_time)
    eventsPerSecond = batch_count/elapsed_time
    #puts "\t\t-->> Started run: #{@@start_time}\t#{elapsed_time} seconds elapsed\t#{eventsPerSecond} events processed per second."
    #puts "\t\t-->> First word cache: #{@@cached_words.keys.count}"
    if @inserted_last_run > eventsPerSecond then
      @bulk_insert_size = (@bulk_insert_size > 20 ? @bulk_insert_size - 20 : 20)
    else
      @bulk_insert_size += 20
    end
    @inserted_last_run = eventsPerSecond
    Statistic.logEventsPerSecond(eventsPerSecond)
    if @@timestamp_parse_failures > 0 then
      Rails.logger.warn "Dropped #{@@timestamp_parse_failures} line(s) with no recognizable timestamp."
    end
    @@start_time = Time.now
    @@current_year = "#{Time.new.year}"
    self.prune_words if @@num_cached > CACHESIZE
  end

  # Flushes, then waits for every outstanding INSERT thread. The importer calls
  # this before exiting: without it the last flush's thread can still be running
  # when the process ends, and that batch is lost with it.
  def self.flush_and_wait
    performPendingInserts
    join_insert_threads
  end
  
  # Drops word-cache entries not used within @@cachelifetime seconds, then
  # adapts that lifetime so the cache hovers near CACHESIZE entries: if pruning
  # removed a lot, entries are being reused and the TTL is lengthened; if it
  # removed little, the TTL is shortened. Prints diagnostics to stdout, which is
  # the importer's log. Called from performPendingInserts when the cache exceeds
  # CACHESIZE.
  def self.prune_words
    current_time = Time.now
    prune_time = current_time - @@cachelifetime
    @@cached_words = @@cached_words.select{|k,v| v[:last] > prune_time }
    pruned_count = CACHESIZE - @@cached_words.keys.count
    Rails.logger.info "Pruned approximately #{pruned_count}."
    if pruned_count > (CACHESIZE / 3) then
      @@cachelifetime += 1
      Rails.logger.info "Cache lifetime increased to #{@@cachelifetime}."
    else 
      @@cachelifetime -= 1
      Rails.logger.info "Cache lifetime decreased to #{@@cachelifetime}."
    end
    Rails.logger.info "There have been #{@cache_hits} hits in the word cache."
    Rails.logger.info "Inserted last run EPS: #{@inserted_last_run}"
    @@num_cached = @@cached_words.keys.count
  end
  
end

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
  @added = 0
  @cache_hits = 0
  @@num_cached = 0
  # Word-cache size that triggers a prune, and the current TTL in seconds.
  # prune_words grows/shrinks the TTL to keep the cache near CACHESIZE.
  CACHESIZE=100000
  @@cachelifetime=320
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
  @@cached_words = Hash.new
  @@num_last_events = 50
  @added = 0
  @cache_hits = 0
  @@num_cached = 0
  CACHESIZE=100000
  @@cachelifetime=320
  @@insertThreads = Array.new
  @inserted_last_run = 100
  @@nextEventID = -1
  @@pendingEventValues = Array.new
  @@system_cache = Hash.new
  @@service_cache = Hash.new
  @@events_words = Array.new
  @@start_time = Time.now
  @display_helper = nil       # Using lazy initialization but still using instance vars so that we
  @event_fields = nil         # instantiate lazily but still only do one SQL query per event
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
  def self.recent_events
    @@num_last_events = Preference.eventsDashboard
    exclusions = Exclusion.pluck(:pattern)
    reg = Regexp.union(exclusions)
    events = (Event.last(@@num_last_events).map { |a| a.hunks }).reject { |event| event.match(reg)}
    @@num_last_events += @@num_last_events * 0.10 if events.count < 50
    @@num_last_events -= @@num_last_events * 0.05 if events.count > 70
    Preference.eventsDashboard(@@num_last_events)
    return events
  end

  # Cheap total event count for the dashboard, read from Postgres statistics
  # rather than COUNT(*).
  #
  # Postgres-only: it queries pg_stat_user_tables and assumes the events table is
  # partitioned as events_p*. On sqlite or an unpartitioned Postgres install this
  # raises or returns nil. The value is an estimate and lags real inserts.
  def self.approximate_count
    connection = ActiveRecord::Base.connection
    # Postgresql performance on a count is awful.  Estimating based on tuples.
    # This is a breaking change for Maria/MySQL.
    sql = "SELECT SUM(n_live_tup) FROM pg_stat_user_tables where relname like 'events_p%';"
    count = connection.execute(sql)
    count.first["sum"].to_i
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
    @@insertThreads.each { |t| t.join }
    @@insertThreads = Array.new
    @@current_year = Time.new.year
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
    binds << [nil, starting_time.to_s(:db)] << [nil, ending_time.to_s(:db)]
    terms.each { |term| binds.concat(word_binds(term)) }
    binds << [nil, terms.count]
    [sql, binds]
  end

  # Range bounds plus the escaped LIKE pattern for one search term.
  def self.word_binds(term)
    [
      [nil, term],
      [nil, term + PREFIX_UPPER],
      [nil, "#{sanitize_sql_like(term)}%"],
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
    scoped = sanitize_sql_array(["id in (#{sql})", *binds.map(&:last)])
    Event.where(scoped).order(generated: :asc).limit(limit).offset(offset)
  end
  private_class_method :matching_events

  # Parses one raw log line and stages it for insertion.
  #
  # This is the ingestion entry point, called once per line by import_syslog.rb.
  # It does not return a meaningful value and silently drops lines it cannot
  # parse (too few fields, unparseable timestamp, empty service) -- that is
  # deliberate: a live syslog feed must never stop on a malformed line.
  #
  # Steps: normalise the text, detect the timestamp format (three are supported),
  # resolve the System and Service, map each unique token to a word id, then
  # append to the pending batches. Nothing is written until the batch reaches
  # @bulk_insert_size, at which point performPendingInserts flushes it.
  #
  # +eventString+ must begin with the originating host, followed by the timestamp
  # and service, e.g. "host.example.com Jun  1 12:00:00 sshd[123]: ...".
  def self.storeEvent(eventString)
    # This next line is to seek and destroy invalid UTF-8 byte sequences.  They seem to show up in some
    # logs, sometimes in URLs.
    eventString = eventString.encode('UTF-8', :invalid => :replace)
    eventString.tr!("\r\n", "")
    hunks = eventString.dup
    eventString.downcase!
    eventString.gsub!(/([^a-zA-Z0-9 \-_:@\*\/.])/," " )
    split_text = eventString.split(/\s+/)
    # The service name's position depends on how many tokens the timestamp
    # occupies, so it is inferred from which timestamp format was detected.
    service_offset = 5 # Assume the service is here. It adjusts based on where the timestamp is found
    if split_text.count < 5 then
      puts "Invalid for syslog format: Too few fields -> " << eventString
      return
    end
    return unless split_text.size > 1 # If there's no date and only an IP then it's not a valid message.
    # Three timestamp dialects are recognised, in this order:
    #   1. ISO 8601 ("2015-06-01T12:00:00.000Z") -- 1 token, service at offset 3
    #   2. RFC with an explicit year in 2015-2019 ("Jun 01 2015 12:00:00") -- 4 tokens
    #   3. Classic syslog, no year ("Jun  1 12:00:00") -- 3 tokens, year assumed
    # The hard-coded 2015-2019 window in branch 2 is a known defect
    # (RECOMMENDATIONS.md 2.2): dates outside it fall through to branch 3.
    if split_text[1] =~ /20[0-9][0-9]-[0-1][0-9]-[0-3][0-9]t[0-9][0-9]:[0-9][0-9]:[0-9][0-9]\.[0-9][0-9][0-9]z/ then
      timestamp = DateTime.parse(split_text[1])
      service_offset = 3
    elsif split_text[3].to_i > 2014 && split_text[3].to_i < 2020 then
      txttimestamp = split_text[1..4].join(' ')
      begin
        timestamp = DateTime.parse(txttimestamp << " GMT")
      rescue Exception => e
        #puts "#{e}: #{eventString}"
        return
      end
    else
      txttimestamp = split_text[1..3].join(' ')
      begin
        timestamp = DateTime.parse("#{txttimestamp} #{@@current_year}  GMT")
      rescue Exception => e
        #puts "#{e}: #{eventString}"
        return
      end
    end
    txtsystem = split_text[0]
    if @@system_cache.has_key?(txtsystem) then
      system = @@system_cache[txtsystem]
    else
      system = System.find_or_add(txtsystem)
      @@system_cache[txtsystem] = system
    end
    txtservice = split_text[service_offset]
    if txtservice.nil? then
      puts "Service empty: " << eventString
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
      if Event.all.count == 0 then
        @@nextEventID = 1
      else
        @@nextEventID = Event.order(id: :desc).limit(1)[0].id + 1 if @@nextEventID == -1
      end
    end

    # Precalculate some needed values and perform necessary conversions.
    timestamp_s = timestamp.to_s(:db)
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
                             :generated => timestamp_s, :stored => time_now.to_s(:db), :hunks => hunks}

    @@nextEventID += 1
    self.performPendingInserts if @@pendingEventValues.count >= @bulk_insert_size
  end

  # Builds a single multi-row INSERT plus its bind parameters. Only the table
  # and column names (all literals from this file) reach the SQL text; every
  # value is bound. SQLite caps host parameters far above the largest batch
  # this produces, so batching is preserved.
  def self.insertStatement(table, columns, rows)
    row_placeholder = "(#{(['?'] * columns.size).join(', ')})"
    sql = "INSERT INTO #{table} (#{columns.join(', ')}) VALUES " +
      Array.new(rows.size) { row_placeholder }.join(', ')
    binds = rows.flat_map { |row| columns.map { |c| [nil, row[c]] } }
    [sql, binds]
  end

  # Writes the staged event and events_words batches, then resets them.
  #
  # Called automatically by storeEvent once a batch is full, and explicitly by
  # import_syslog.rb at the end of each pass (and on Ctrl-C) so nothing is left
  # in memory. Outside the test environment the two INSERTs run on a background
  # thread so ingestion is not blocked by the write; threads are joined once more
  # than five have accumulated.
  #
  # After each flush it retunes @bulk_insert_size (+20 when throughput improved,
  # -20 down to a floor of 20 when it fell) and logs the rate as a Statistic.
  def self.performPendingInserts
    return if @@pendingEventValues.count < 1

    if @@insertThreads.count > 5 then
      puts "Joining previous inserts."; 
      @@insertThreads.each { |thread| thread.join }
      @@insertThreads = []
    end
    ew_sql, ew_binds = insertStatement('events_words', [:event_id, :word_id, :generated], @@events_words)
    ev_sql, ev_binds = insertStatement('events', [:id, :system_id, :service_id, :generated, :stored, :hunks], @@pendingEventValues)

    if Rails.env.test?
      # The async insert thread takes a second SQLite connection and deadlocks
      # against DatabaseCleaner's open transaction, and its results are never
      # joined, so tests cannot observe them. Insert inline in test.
      connection = ActiveRecord::Base.connection
      connection.exec_query ew_sql, "SQL", ew_binds
      connection.exec_query ev_sql, "SQL", ev_binds
    else
      @@insertThreads << Thread.new(ew_sql, ew_binds, ev_sql, ev_binds) do |ew_sql, ew_binds, ev_sql, ev_binds|
        connection = ActiveRecord::Base.connection
        connection.exec_query ew_sql, "SQL", ew_binds
        connection.exec_query ev_sql, "SQL", ev_binds
      end
    end

    #puts "\t\t-->> Flushed #{@@pendingEventValues.count} events. <<--"
    elapsed_time = (Time.now - @@start_time)
    eventsPerSecond = @@pendingEventValues.count/elapsed_time
    #puts "\t\t-->> Started run: #{@@start_time}\t#{elapsed_time} seconds elapsed\t#{eventsPerSecond} events processed per second."
    #puts "\t\t-->> First word cache: #{@@cached_words.keys.count}"
    if @inserted_last_run > eventsPerSecond then
      @bulk_insert_size = (@bulk_insert_size > 20 ? @bulk_insert_size - 20 : 20)
    else
      @bulk_insert_size += 20
    end
    @inserted_last_run = eventsPerSecond
    Statistic.logEventsPerSecond(eventsPerSecond)
    @@start_time = Time.now
    @@pendingEventValues = Array.new
    @@events_words = Array.new
    @@current_year = "#{Time.new.year}"
    self.prune_words if @@num_cached > CACHESIZE
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
    puts "\t+++ Pruned approximately #{pruned_count}."
    if pruned_count > (CACHESIZE / 3) then
      @@cachelifetime += 1
      puts "\t+++ Cache lifetime increased to #{@@cachelifetime}."
    else 
      @@cachelifetime -= 1
      puts "\t+++ Cache lifetime decreased to #{@@cachelifetime}."
    end
    puts "\t+++ There have been #{@cache_hits} hits in the word cache."
    puts "\t>>> Inserted last run EPS: #{@inserted_last_run}"
    @@num_cached = @@cached_words.keys.count
  end
  
end

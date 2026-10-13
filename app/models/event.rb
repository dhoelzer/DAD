class Event < ActiveRecord::Base
  has_and_belongs_to_many :words
  has_and_belongs_to_many :alerts
  belongs_to :system
  belongs_to :service

  @bulk_insert_size=((Rails.env.development? || Rails.env.test?) ? 1 : 2000)
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
  
  def self.event_pruning_count
    @@num_last_events
  end
  
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

  def self.approximate_count
    connection = ActiveRecord::Base.connection
    # Postgresql performance on a count is awful.  Estimating based on tuples.
    # This is a breaking change for Maria/MySQL.
    sql = "SELECT SUM(n_live_tup) FROM pg_stat_user_tables where relname like 'events_p%';"
    count = connection.execute(sql)
    count.first["sum"].to_i
  end

  def self.hidden?(current_user = nil)
    return true if current_user.nil?
    return true unless current_user.has_right?("Viewer")
    return false
  end
  
  def display_helper
    @display_helper = @display_helper.nil? ? Display.helper_for_event(self.hunks) : @display_helper
    @display_helper
  end
  
  def use_display_helper?
    return (self.display_helper.nil? ? false : true)
  end
  
  def parsed
    @display_helper = self.display_helper
    return "BAD DISPLAY FILTER" if @display_helper.nil?
    eval @display_helper.display_script
    parse_event(self.hunks)
  end
  
  def event_fields
    return @event_fields unless @event_fields.nil?
    @event_fields = self.hunks.split(/ +/)
    @event_fields
  end
  
  def reconstitute
    return self.hunks
  end
  
  def inspect
    string = "#{self.system.display_name}|#{self.generated}|#{self.hunks}"
    return string
  end

  def self.diskUtilization
    `df -m | egrep "\s+/$"`.split(/\s+/)[4].to_i
  end
  
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
  def self.search(search_string, starting_time=(Time.now - 1.hour), offset=0, limit=100)
    terms = search_string.downcase.split(/\s+/)
    return [] if terms.empty?
    matching_events(terms, starting_time, Time.now, offset, limit)
  end

  def self.search_period(search_string, starting_time, ending_time, offset=0, limit=100)
    terms = search_string.downcase.split(/\s+/)
    return [] if terms.empty?
    matching_events(terms, starting_time, ending_time, offset, limit)
  end

  def self.matching_events(terms, starting_time, ending_time, offset, limit)
    sql, binds = searchSQL(starting_time, ending_time, terms)
    scoped = sanitize_sql_array(["id in (#{sql})", *binds.map(&:last)])
    Event.where(scoped).order(generated: :asc).limit(limit).offset(offset)
  end
  private_class_method :matching_events

  def self.storeEvent(eventString)
    # This next line is to seek and destroy invalid UTF-8 byte sequences.  They seem to show up in some
    # logs, sometimes in URLs.
    eventString = eventString.encode('UTF-8', :invalid => :replace)
    eventString.tr!("\r\n", "")
    hunks = eventString.dup
    eventString.downcase!
    eventString.gsub!(/([^a-zA-Z0-9 \-_:@\*\/.])/," " )
    split_text = eventString.split(/\s+/)
    service_offset = 5 # Assume the service is here. It adjusts based on where the timestamp is found
    if split_text.count < 5 then
      puts "Invalid for syslog format: Too few fields -> " << eventString
      return
    end
    return unless split_text.size > 1 # If there's no date and only an IP then it's not a valid message.
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

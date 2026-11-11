# Turns one raw syslog line into an Event row plus its events_words index rows.
#
# Extracted from Event (RECOMMENDATIONS 4.1). Event is the model and the read
# side -- associations, search, the dashboard feed. This is the write side: the
# parse/tokenise/stage/flush pipeline that import_syslog.rb drives once per line.
#
# State is class-level, so it is process-global: this is built to be driven by a
# single long-running importer, which is how it has always worked. Making it
# instance-based would mean deciding which instance the admin jobs
# (prune_words, reset_caches) address, for no benefit to the read path. What the
# extraction buys is that the state is now private to one class with a named API,
# instead of 16 class variables on the model that tests reached into directly.
#
# All of it is held in class-level instance variables now. The model mixed
# @@ variables with @ ones for no reason -- @bulk_insert_size and @@cachelifetime
# sat side by side with the same lifetime -- and @@ made the state reachable from
# subclasses and from outside via class_variable_get.
#
# Ingest is at-least-once, not exactly-once: see "Ingest semantics" in the README
# and RECOMMENDATIONS 2.2. The ordering that produces that guarantee -- the
# checkpoint advancing only after a batch's rows are durable -- lives in
# performPendingInserts and advance_checkpoint! below.
class EventIngestor
  # Rows per INSERT batch. Starts at 1 in dev/test (so tests can observe writes
  # immediately) and 2000 in production; performPendingInserts retunes it to
  # track throughput.
  DEFAULT_BULK_INSERT_SIZE = (Rails.env.development? || Rails.env.test?) ? 1 : 2000

  # Batches allowed in flight at once.
  #
  # One still keeps a batch writing while the main thread parses the next one,
  # which is the point of the threads, without ever holding two write
  # transactions at the same time. The old limit of 5 meant 5 insert threads plus
  # the main thread could ask for 6 connections from a pool of 5, so a flush
  # would block on the pool timeout instead of writing. It was pinned to 1 while
  # the test suite ran SQLite, which permits a single writer; Postgres would
  # allow more, but the pipeline has only ever been exercised at 1, and the
  # checkpoint ordering rules in test/models/event_ingest_backpressure_test.rb
  # are written against it.
  MAX_INSERT_THREADS = 1

  # Word-cache size that triggers a prune, and the TTL it starts at in seconds.
  # prune_words grows/shrinks the TTL to keep the cache near CACHESIZE.
  CACHESIZE = 100000

  # Starting TTL. 320 is the value the pre-extraction Event model used
  # (@@cachelifetime=320); the extraction moved the reader and writer but dropped
  # the assignment, leaving @cachelifetime nil, so the first prune_words raised
  # "can't convert NilClass into an exact number" and took the importer down.
  DEFAULT_CACHE_LIFETIME = 320

  # Host-parameter ceilings per statement, per adapter. A multi-row INSERT with C
  # columns and R rows uses C*R parameters, and exceeding the ceiling is a hard
  # error, not a slowdown. Postgres caps a statement at 65535 parameters (Int16)
  # -- measured on the real insert path by binary search over events_words
  # INSERTs. At the ~16 index rows per event this tokenizer produces, the
  # production default batch of 2000 events needs ~96k parameters, so the
  # ceiling is not hypothetical: without chunking, a default-sized batch cannot be
  # inserted at all.
  MAX_STATEMENT_PARAMS = {
    'PostgreSQL' => 65_535
  }.freeze

  # Used for adapters not listed above: the lowest ceiling this app supports, so
  # an unknown adapter chunks conservatively rather than dying mid-batch.
  DEFAULT_MAX_STATEMENT_PARAMS = 32_766

  # Year assumed for syslog lines that carry a timestamp without a year
  # (the classic "Jun  1 12:00:00" form). Refreshed on each flush so a long
  # ingest run does not misdate lines across a year boundary.
  #
  # Kept as an Integer: parse_timestamp takes year.to_i, and the previous code
  # declared an Integer here but reassigned a String on every flush.
  def self.current_year
    @current_year
  end

  # Guards @insertThreads and the checkpoint sidecar: writer threads advance the
  # checkpoint concurrently with the main thread. A lock rather than cache, so
  # it is created once here and deliberately never reset -- replacing it while a
  # writer thread holds it would let two threads advance the checkpoint at once.
  @checkpoint_mutex = Mutex.new

  def self.resetCaches
    @cached_words = Hash.new
    @num_cached = 0
    @nextEventID = -1
    @pendingEventValues = Array.new
    @system_cache = Hash.new
    @service_cache = Hash.new
    @events_words = Array.new
    # Tokens whose word id is not known yet, held until the batch is flushed so
    # they can be resolved in bulk. See resolve_staged_words.
    @staged_tokens = Array.new
    # Array() rather than a bare each: resetCaches runs once at load, before
    # @insertThreads has ever been assigned.
    Array(@insertThreads).each { |batch| batch.thread.join }
    @insertThreads = Array.new
    @checkpoint_writer = nil
    @ingest_position = 0
    @ingest_checkpoint = 0
    @current_year = Time.new.year
    @timestamp_parse_failures = 0
    # @bulk_insert_size grows adaptively with throughput; without a reset, a
    # single storeEvent can sit in the pending set indefinitely.
    @bulk_insert_size = DEFAULT_BULK_INSERT_SIZE
    # Must be set here, not only by prune_words: prune_words reads it before it
    # writes it, so a process that never set it dies on its first prune.
    @cachelifetime = DEFAULT_CACHE_LIFETIME
    @max_statement_params = nil
    @inserted_last_run = 100
    @cache_hits = 0
    resetStats
  end

  # Restarts the throughput clock used to compute events/sec in
  # performPendingInserts. Call after a burst that should not count, e.g. at the
  # start of an import_syslog.rb pass.
  def self.resetStats
    @start_time = Time.now
  end

  # --- introspection -------------------------------------------------------
  #
  # Before this extraction, tests asserted on the shape of the storage by
  # reaching through class_variable_get, which coupled them to the mechanism
  # rather than the behaviour. These are the supported way in: they report
  # counts and ids, not the arrays themselves, so the storage can change without
  # breaking a caller.

  # Event rows staged but not yet handed to a writer.
  def self.pending_count
    pending_event_values.count
  end

  # Ids staged for the pending event rows, in the order they will be written.
  def self.pending_ids
    pending_event_values.map { |row| row[:id] }
  end

  # events_words rows staged but not yet handed to a writer.
  #
  # Excludes tokens still awaiting resolution, so it is only complete once
  # resolve_staged_words has run for the batch. #pending_token_count is the
  # other half.
  def self.staged_words_count
    events_words.count
  end

  # Tokens staged but not yet resolved to word ids.
  def self.pending_token_count
    staged_tokens.sum { |_event_id, _generated, list| list.size }
  end

  # Batches handed to a writer thread and not yet joined.
  def self.in_flight_count
    checkpoint_mutex.synchronize { insert_threads.count }
  end

  # Next primary key that will be assigned. -1 means "not yet derived from the
  # table", which is the state after resetCaches.
  def self.next_event_id
    @nextEventID
  end

  # Lines dropped because no timestamp format matched.
  def self.timestamp_parse_failures
    @timestamp_parse_failures
  end

  def self.cached_word_count
    word_cache.size
  end

  # The word cache itself: term => {id:, last:}.
  #
  # The one place the structure is exposed rather than summarised. prune_words
  # is an operator-facing job whose whole behaviour is the TTL comparison against
  # each entry's :last, and verifying that it drops stale entries and keeps
  # fresh ones requires ageing one entry. Everything else goes through the
  # counts above.
  def self.cached_words
    @cached_words
  end

  def self.num_cached
    @num_cached
  end

  def self.cache_hits
    @cache_hits
  end

  def self.bulk_insert_size
    @bulk_insert_size
  end

  def self.bulk_insert_size=(size)
    @bulk_insert_size = size
  end

  def self.inserted_last_run
    @inserted_last_run
  end

  def self.inserted_last_run=(rate)
    @inserted_last_run = rate
  end

  def self.cache_lifetime
    @cachelifetime
  end

  def self.cache_lifetime=(seconds)
    @cachelifetime = seconds
  end

  # --- the pipeline --------------------------------------------------------

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
  # bulk_insert_size, at which point performPendingInserts flushes it.
  #
  # +eventString+ must begin with the originating host, followed by the timestamp
  # and service, e.g. "host.example.com Jun  1 12:00:00 sshd[123]: ...".
  def self.storeEvent(eventString, position = nil)
    # Staging is all-or-nothing. The word loop appends to @events_words and
    # @staged_tokens before the event row is appended to @pendingEventValues, so
    # a raise part-way through leaves index rows for an event id that never gets
    # an events row (search hits that 404), and @nextEventID is not advanced, so
    # the next line reuses the id and dies on a UNIQUE violation. The importer
    # now skips bad lines instead of exiting, which makes a partially staged
    # line a permanent corruption rather than a one-off crash.
    words_staged = events_words.count
    tokens_staged = staged_tokens.count
    events_staged = pending_event_values.count
    begin
      stage_event(eventString, position)
    rescue StandardError
      # A flush inside stage_event resets all three, so the captured counts can
      # be past the end; slice! then no-ops, which is the correct outcome (those
      # rows are already handed off, not partial).
      events_words.slice!(words_staged..-1)
      staged_tokens.slice!(tokens_staged..-1)
      pending_event_values.slice!(events_staged..-1)
      raise
    end
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
    @checkpoint_writer = checkpoint_writer
    @ingest_position = resume_offset
  end

  # Flushes, then waits for every outstanding INSERT thread. The importer calls
  # this before exiting: without it the last flush's thread can still be running
  # when the process ends, and that batch is lost with it.
  def self.flush_and_wait
    performPendingInserts
    join_insert_threads
  end

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

  # Builds a single multi-row INSERT plus its bind parameters. Only the table
  # and column names (all literals from this file) reach the SQL text; every
  # value is bound.
  #
  # Callers that write a whole staged batch want insert_statements, which caps
  # the result at the adapter's parameter ceiling; this is the per-statement
  # builder underneath it.
  # Binds are plain values: Rails 7.1 removed the legacy [type, value] pair form
  # that exec_query accepted, and type_cast now raises "can't cast Array" on it.
  def self.insertStatement(table, columns, rows)
    row_placeholder = "(#{(['?'] * columns.size).join(', ')})"
    sql = "INSERT INTO #{table} (#{columns.join(', ')}) VALUES " +
      Array.new(rows.size) { row_placeholder }.join(', ')
    binds = rows.flat_map { |row| columns.map { |c| row[c] } }
    [sql, binds]
  end

  # The staged rows as one or more INSERTs, each within the adapter's host
  # parameter ceiling.
  #
  # A single multi-row INSERT for a whole batch is not always legal: R rows over
  # C columns uses C*R parameters, and the database rejects the statement
  # outright once the ceiling is passed. events_words is the binding constraint at
  # three columns and ~16 rows per event, so a 2000-event batch -- the production
  # default -- needs ~96k parameters against Postgres' ceiling of 65535. Chunking
  # is what lets bulk_insert_size mean "rows per
  # transaction" rather than "rows per statement".
  #
  # Empty input yields no statements rather than an INSERT with no VALUES, which
  # is a syntax error.
  def self.insert_statements(table, columns, rows, max_params: max_statement_params)
    return [] if rows.empty?
    rows_per_statement = [max_params / columns.size, 1].max
    rows.each_slice(rows_per_statement).map { |slice| insertStatement(table, columns, slice) }
  end

  # Parameter ceiling for the connection in use. Computed on the calling thread
  # before a batch is handed to a writer, so the chunking decision does not
  # depend on which thread happens to hold the connection.
  def self.max_statement_params
    @max_statement_params ||
      MAX_STATEMENT_PARAMS.fetch(ActiveRecord::Base.connection.adapter_name,
                                 DEFAULT_MAX_STATEMENT_PARAMS)
  end

  # Overrides the ceiling. Tests use it to force chunking at a batch size the
  # suite can actually stage; leaving it nil restores adapter lookup.
  def self.max_statement_params=(limit)
    @max_statement_params = limit
  end

  # Drops word-cache entries not used within cache_lifetime seconds, then
  # adapts that lifetime so the cache hovers near CACHESIZE entries: if pruning
  # removed a lot, entries are being reused and the TTL is lengthened; if it
  # removed little, the TTL is shortened. Logs to Rails.logger, which the
  # importer broadcasts to the journal. Called from performPendingInserts when
  # the cache exceeds CACHESIZE.
  def self.prune_words
    current_time = Time.now
    prune_time = current_time - cache_lifetime
    @cached_words = word_cache.select { |k, v| v[:last] > prune_time }
    pruned_count = CACHESIZE - word_cache.size
    Rails.logger.info "Pruned approximately #{pruned_count}."
    if pruned_count > (CACHESIZE / 3) then
      self.cache_lifetime = cache_lifetime + 1
      Rails.logger.info "Cache lifetime increased to #{cache_lifetime}."
    else
      self.cache_lifetime = cache_lifetime - 1
      Rails.logger.info "Cache lifetime decreased to #{cache_lifetime}."
    end
    Rails.logger.info "There have been #{cache_hits} hits in the word cache."
    Rails.logger.info "Inserted last run EPS: #{inserted_last_run}"
    @num_cached = word_cache.size
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
    checkpoint_mutex.synchronize do
      while (entry = insert_threads.first)
        break unless entry.finished
        insert_threads.shift
        @ingest_checkpoint = entry.position
        @checkpoint_writer&.call(entry.position)
      end
    end
  end

  # Replaces the in-flight queue.
  #
  # A seam, not part of the pipeline. The head-of-queue ordering rule in
  # advance_checkpoint! cannot be driven through the real path: with
  # MAX_INSERT_THREADS at 1 there is only ever one batch in flight, so the
  # head-of-queue rule is not exercised by the pipeline. Raising that constant to
  # 2 is the obvious throughput change, and the ordering rule is what must not
  # break when someone does.
  def self.in_flight_queue=(batches)
    checkpoint_mutex.synchronize { @insertThreads = batches }
  end

  # Installs the checkpoint writer directly.
  #
  # The other half of the seam above: begin_ingest is the only normal way this is
  # set, and it drains the previous file first, so a test that wants to observe
  # advance_checkpoint! releasing a hand-built queue has to install the writer
  # without that drain.
  def self.checkpoint_writer=(writer)
    @checkpoint_writer = writer
  end

  # One staged batch on its way to the database.
  #
  # +position+ is the byte offset of the last line the batch covers; +finished+
  # is set by the thread once its rows are committed, which is what makes the
  # batch eligible to advance the checkpoint.
  IngestBatch = Struct.new(:thread, :position, :finished)

  def self.performPendingInserts
    # Surface a batch that already failed before staging any more work.
    join_insert_threads if insert_threads.any? { |b| !b.thread.alive? }

    return if pending_event_values.count < 1

    if insert_threads.count >= MAX_INSERT_THREADS then
      Rails.logger.debug "Joining previous inserts."
      join_insert_threads
    end
    resolve_staged_words
    ew_statements = insert_statements('events_words', [:event_id, :word_id, :generated], events_words)
    ev_statements = insert_statements('events', [:id, :system_id, :service_id, :generated, :stored, :hunks],
                                      pending_event_values)

    # Measured before the queues are cleared: the throughput figure below needs
    # the size of the batch just handed off. Reading @pendingEventValues after
    # the reset yields 0, which zeroed every logged rate and let
    # @bulk_insert_size climb without bound.
    batch_count = pending_event_values.count

    # Cleared as soon as the rows are captured into the statements, before the
    # stats bookkeeping below. Statistic.logEventsPerSecond writes to the same
    # database and can fail; when it raised, the rows it had *already* handed to
    # a writer thread were still staged, so the next flush inserted them a
    # second time under the same explicit ids and died on
    # UNIQUE constraint failed: events.id. Reproduced on SQLite under a
    # crash-then-reclaim run.
    @pendingEventValues = Array.new
    @events_words = Array.new

    if Rails.env.test?
      # Inline rather than on a writer thread: the suite's cleanup runs inside an
      # open transaction, and a second connection writing concurrently makes the
      # ordering of these writes nondeterministic between runs. Inline keeps the
      # same write_batch path, just without the thread.
      write_batch(ew_statements, ev_statements)
      # Inline: the rows are durable the moment write_batch returns.
      checkpoint_mutex.synchronize do
        @ingest_checkpoint = @ingest_position
        @checkpoint_writer&.call(@ingest_position)
      end
    else
      # The batch reaches the thread by value, and the queues are cleared only
      # after the handoff, so the thread owns its own rows and no later reset
      # can pull them out from under it.
      batch = IngestBatch.new(nil, @ingest_position, false)
      # Queued before the thread starts. If the write finished first, the thread
      # would call advance_checkpoint! against a queue that does not yet hold
      # this batch and its checkpoint would never be released.
      checkpoint_mutex.synchronize { @insertThreads << batch }
      batch.thread = Thread.new(ew_statements, ev_statements, batch) do |ew_statements, ev_statements, batch|
        begin
          write_batch(ew_statements, ev_statements)
          # Rows are durable: this batch may now release the checkpoint, but
          # only if every earlier batch has already finished.
          batch.finished = true
          EventIngestor.advance_checkpoint!
          nil
        rescue Exception => e
          # Thread#value returns a raised exception rather than re-raising it;
          # join_insert_threads turns that back into a real failure. A failed
          # batch never advances the checkpoint, so its lines get re-read.
          e
        end
      end
    end
    elapsed_time = (Time.now - start_time)
    eventsPerSecond = batch_count / elapsed_time
    if inserted_last_run > eventsPerSecond then
      self.bulk_insert_size = (bulk_insert_size > 20 ? bulk_insert_size - 20 : 20)
    else
      self.bulk_insert_size = bulk_insert_size + 20
    end
    self.inserted_last_run = eventsPerSecond
    Statistic.logEventsPerSecond(eventsPerSecond)
    if timestamp_parse_failures > 0 then
      Rails.logger.warn "Dropped #{timestamp_parse_failures} line(s) with no recognizable timestamp."
    end
    @start_time = Time.now
    @current_year = Time.new.year
    prune_words if num_cached > CACHESIZE
  end

  # --- internals -----------------------------------------------------------

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
    timestamp, consumed = parse_timestamp(split_text[1..-1], current_year)
    if timestamp.nil? then
      @timestamp_parse_failures = timestamp_parse_failures + 1
      return
    end
    service_offset = 1 + consumed
    txtsystem = split_text[0]
    if system_cache.has_key?(txtsystem) then
      system = system_cache[txtsystem]
    else
      system = System.find_or_add(txtsystem)
      system_cache[txtsystem] = system
    end
    txtservice = split_text[service_offset]
    if txtservice.nil? then
      Rails.logger.warn "Service empty: #{eventString}"
      return
    end
    txtservice = txtservice.tr("^a-zA-Z\-_/","")
    if service_cache.has_key?(txtservice) then
      service = service_cache[txtservice]
    else
      service = Service.find_or_add(txtservice)
      service_cache[txtservice] = service
    end

    # Is this the first event inserted? If so, figure out what the maximum ID is right now.
    # Events are assigned ids explicitly so events_words rows can be staged ahead of
    # the event row; the counter must not collide with existing rows.
    if @nextEventID == -1 then
      # maximum(:id) is MAX(id) over the primary key. The previous Event.all.count
      # was a full table scan on every importer restart, on a table sized in the
      # hundreds of millions.
      @nextEventID = (Event.maximum(:id) || 0) + 1
    end

    # Precalculate some needed values and perform necessary conversions.
    timestamp_s = timestamp.to_fs(:db)
    time_now = Time.now

    # Take all of the words, make them unique. Cached ones are stamped and
    # indexed immediately; uncached ones are held with the event they came from
    # until the batch is flushed, so the words table is hit once per batch
    # rather than once per token. See resolve_staged_words.
    deferred = nil
    split_text.to_set.to_a.each do |word|
      word = Word.truncate_for_column(word)
      if word_cache.key?(word) then
        word_cache[word][:last] = time_now
        @cache_hits = cache_hits + 1
        events_words << { :event_id => @nextEventID, :word_id => word_cache[word][:id],
                          :generated => timestamp_s }
      else
        (deferred ||= []) << word
      end
    end
    # One entry per event, and only when that event has something to resolve:
    # the token strings are shared across the batch instead of copied per row.
    staged_tokens << [@nextEventID, timestamp_s, deferred] if deferred
    # Values are staged as-is and bound as parameters at flush time, so log text
    # (which is attacker-controlled) never becomes part of the SQL string.
    pending_event_values << { :id => @nextEventID, :system_id => system.id, :service_id => service.id,
                              :generated => timestamp_s, :stored => time_now.to_fs(:db), :hunks => hunks }

    @nextEventID += 1
    # Set before the flush so the batch being handed off carries this line's
    # offset. Lines the parser skipped leave it behind; the next staged line
    # covers them, since offsets only move forward.
    @ingest_position = position if position
    performPendingInserts if pending_event_values.count >= bulk_insert_size
  end
  private_class_method :stage_event

  # Turns the tokens staged since the last flush into events_words rows.
  #
  # The reason ingest is not dominated by the words table. stage_event cannot
  # resolve a token it has not seen before without a round-trip, so it defers
  # it; this resolves the whole batch at once -- one indexed IN lookup and one
  # multi-row INSERT per Word::RESOLVE_CHUNK tokens, instead of one lookup plus
  # one autocommit INSERT per token. On a cold word cache that is the difference
  # between tens of thousands of statements and a handful.
  #
  # Runs on the main thread, before the batch is handed to a writer: the words
  # table is read and written here, so doing it inside the writer thread would
  # contend with the batch it is preparing and make the checkpoint ordering
  # harder to reason about.
  #
  # A token that turns out to be new is added to the word cache, which is what
  # keeps the next batch off the database entirely.
  #
  # All-or-nothing, like stage_event: the rows are built in a local array and
  # appended only once every token has an id. A failure part-way through
  # therefore leaves the batch exactly as it was, which matters because the
  # importer's line-level rescue calls flush_and_wait -- if this had already
  # appended some rows, the retry would append them a second time and search
  # would return the same event twice. Word.resolve_ids is itself idempotent
  # against rows it inserted on the failed attempt, since they are found by the
  # lookup rather than re-inserted.
  def self.resolve_staged_words
    return if staged_tokens.empty?

    tokens = staged_tokens.flat_map { |_event_id, _generated, list| list }
    ids = Word.resolve_ids(tokens)

    rows = Array.new
    staged_tokens.each do |event_id, generated, list|
      list.each do |token|
        word_id = ids[token]
        # A nil here would write a NULL word_id: an index row no search can
        # ever match. Word.resolve_ids re-plucks when RETURNING comes back
        # short, so reaching this means the row genuinely is not there.
        raise "word #{token.inspect} staged but not resolved" if word_id.nil?

        rows << { :event_id => event_id, :word_id => word_id, :generated => generated }
      end
    end
    events_words.concat(rows)

    time_now = Time.now
    new_words = ids.keys - word_cache.keys
    new_words.each { |token| word_cache[token] = { :id => ids[token], :last => time_now } }
    @num_cached = num_cached + new_words.count

    @staged_tokens = Array.new
  end
  private_class_method :resolve_staged_words

  # Writes one staged batch. Everything in the batch shares a transaction:
  # events_words is written first, so a crash between the two left index rows
  # pointing at events that do not exist -- search hits that 404. Chunking a
  # batch into several statements (insert_statements) must not break that, so the
  # transaction wraps the whole set, not each statement.
  #
  # Takes the statements as arguments instead of reading the class-level queues,
  # so a caller can hand a batch to a thread without the queues changing
  # underneath it. Internal: the only writer of a staged batch.
  def self.write_batch(ew_statements, ev_statements)
    ActiveRecord::Base.transaction do
      ew_statements.each { |sql, binds| SqlPlaceholders.query(sql, binds) }
      ev_statements.each { |sql, binds| SqlPlaceholders.query(sql, binds) }
    end
  end
  private_class_method :write_batch

  # Joins every outstanding INSERT thread and re-raises the first failure any
  # of them recorded.
  #
  # A thread that died holding a batch means those events are gone, so the
  # failure is surfaced rather than swallowed: the importer stops with its logs
  # still in LogsToProcess instead of carrying on as if the write succeeded.
  # Silent loss is the worse outcome for a tool whose whole job is to keep
  # these lines.
  def self.join_insert_threads
    pending = checkpoint_mutex.synchronize { insert_threads.dup }
    failures = pending.map do |batch|
      batch.thread.join
      batch.thread.value
    end.compact
    checkpoint_mutex.synchronize { @insertThreads = [] }
    raise failures.first unless failures.empty?
  end
  private_class_method :join_insert_threads

  # Readers over the state resetCaches initialises. Class-level ivars rather
  # than class variables: same process-global lifetime, but private to this
  # class, so nothing outside it can reach through them the way tests reached
  # into Event's @@ variables.
  def self.pending_event_values
    @pendingEventValues
  end

  def self.events_words
    @events_words
  end

  def self.staged_tokens
    @staged_tokens
  end

  def self.word_cache
    @cached_words
  end

  def self.system_cache
    @system_cache
  end

  def self.service_cache
    @service_cache
  end

  def self.insert_threads
    @insertThreads
  end

  def self.checkpoint_mutex
    @checkpoint_mutex
  end

  def self.start_time
    @start_time
  end

  private_class_method :pending_event_values, :events_words, :staged_tokens, :word_cache,
                       :system_cache,
                       :service_cache, :insert_threads, :checkpoint_mutex,
                       :start_time

end

EventIngestor.resetCaches

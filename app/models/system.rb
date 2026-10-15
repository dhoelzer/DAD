# A host that sends syslog lines, identified by the address it appears to come
# from (the first token of the line, usually a hostname or IP).
#
# Populated during ingestion via System.find_or_add. Every Event carries a
# system_id, so the dashboard's per-host views are plain joins. A System is
# considered "unreachable" when it produces no events within a lookback window
# (see System.with_events_within_hours and Alert.hostUnreachable).
class System < ActiveRecord::Base
  has_many :events
  has_many :services, :through => :events

  # Process-local memo of address -> System row for the ingestion hot path.
  # Never expired; cleared only by restarting the importer. See Event.resetCaches,
  # which must clear this when the database is rolled back, since the cache keys
  # on rows that may no longer exist.
  @@cached_stuff = Hash.new
  @added = 0

  # Show the "Systems" tab only to users holding the Viewer right.
  def self.hidden?(current_user = nil)
    return true if current_user.nil?
    return true unless current_user.has_right?("Viewer")
    return false
  end

  # Systems that produced at least one event in the last +hours+ hours.
  #
  # Used by the dashboard to decide which hosts to chart. Systems absent from
  # the result are the ones Alert.hostUnreachable flags.
  #
  # One grouped query plus one lookup for all ids, instead of a System.find per
  # group: this runs on every dashboard poll.
  def self.with_events_within_hours(hours=1)
    counts = Event.where("generated > ?", (Time.now()-(hours * 3600)).to_fs(:db)).group(:system_id).count
    reporting = counts.select { |_id, count| count > 0 }.keys
    System.where(id: reporting).to_a
  end

  # Per-system event counts over the last +days+ days, as [system_id, name, count].
  #
  # Ordered by display name. Used by the reporting views; returns an
  # ActiveRecord result set rather than records.
  def self.reportingInLastDays(days)
    connection = ActiveRecord::Base.connection
    events_since = (Time.now - (days * 86400))
    sql = "select system_id,b.name,count(*) as count from events as a join systems as b on  a.system_id=b.id where generated>? group by system_id,b.name order by b.name asc"
    connection.exec_query(sql, "SQL", [events_since.to_fs(:db)])
  end

  # Label for this host: its +name+ if set, else its +address+ in parentheses.
  # Use this in any user-facing output rather than #name, which is often nil.
  def display_name
    return "(#{self.address})" if self.name.nil?
    "#{self.name}"
  end

  # Returns the System at address +new_item+, creating it on first sight.
  #
  # Called from the ingestion hot path (Event.storeEvent) and memoised in
  # @@cached_stuff. Not thread-safe. Note lookup is by +address+, not +name+:
  # +name+ is an operator-assigned label and is not used for identity.
  def self.find_or_add(new_item)
    return @@cached_stuff[new_item] if @@cached_stuff.has_key?(new_item)
    item=System.find_by address: new_item
    if item.nil? then
      item = System.create(:address => new_item)
      @added += 1
    end
    @@cached_stuff[new_item] = item
    return item
  end

  # Shared by #hourly_stats and #events_per_hour. Returns count/bucket rows, where
  # bucket names the hour as "YYYY-MM-DD HH".
  #
  # Buckets with substr(cast(<ts> as text),1,13) rather than extract(): extract() is
  # Postgres-only and SQLite rejects it, which meant these dashboard queries raised
  # on every dev/test run. See ApplicationHelper#statistics_by_hour for the same
  # reasoning.
  def self.hourly_counts(system_id, since)
    sql = "select count(*) as count,substr(cast(generated as text),1,13) as bucket from events where events.system_id=? and events.generated>? group by bucket order by bucket asc"
    ActiveRecord::Base.connection.exec_query sql, "SQL", [system_id, since]
  end

  # Number of Systems memoised in this process (diagnostics/monitoring).
  def self.number_of_cached_items
    return @@cached_stuff.size
  end

  # How many Systems this process has created (diagnostics/monitoring).
  def self.added
    return @added
  end

  # Count of this system's events at or after +since+ (default: last hour).
  def events_since(since=1.hour.ago)
    connection = ActiveRecord::Base.connection
    sql = "select count(*) as count from events where events.system_id=? and generated>?"
    results = connection.exec_query sql, "SQL", [self.id, since]
    return results[0]["count"].to_i
  end

  # This system's hourly event counts since +since+ as [[bucket, count], ...].
  # Shared by #hourly_stats and #events_per_hour so the page fetches the series once.
  def self.hourly_buckets(system_id, since)
    hourly_counts(system_id, since).map { |row| [row['bucket'], row['count']] }
  end

  # This system's hourly event counts since +since+ as [["M/D/YYYY H:00:00", n], ...],
  # ready to hand to a charting library.
  def events_per_hour(since=7.days.ago)
    BucketStats.series(System.hourly_buckets(self.id, since))
  end

  # [mean, variance, standard deviation] of this system's hourly event counts
  # since +since+. Used to spot a host that has become abnormally noisy or quiet.
  #
  # Not derived from the 7-day series #events_per_hour fetches on the same page,
  # even though that would save a query: the SQL counts only the events after the
  # exact +since+ instant, so the bucket straddling it is partial, and that cannot
  # be recovered from already-bucketed rows. Narrowing pre-bucketed data instead
  # would silently change the baseline the gauges compare against.
  def hourly_stats(since=1.day.ago)
    BucketStats.summary(System.hourly_buckets(self.id, since))
  end

end

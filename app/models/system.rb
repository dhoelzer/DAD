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
  # Used by the dashboard to decide which hosts to chart. Returns System records
  # (one query per system_id -- acceptable because the result set is small).
  # Systems absent from the result are the ones Alert.hostUnreachable flags.
  def self.with_events_within_hours(hours=1)
    counts = Event.where("generated > ?", (Time.now()-(hours * 3600)).to_s(:db)).group(:system_id).count
    results = Array.new
    counts.each do |system_id, count|
      results << System.find(system_id) unless count <= 0
    end
    return results
  end

  # Per-system event counts over the last +days+ days, as [system_id, name, count].
  #
  # Ordered by display name. Used by the reporting views; returns an
  # ActiveRecord result set rather than records.
  def self.reportingInLastDays(days)
    connection = ActiveRecord::Base.connection
    events_since = (Time.now - (days * 86400))
    sql = "select system_id,b.name,count(*) as count from events as a join systems as b on  a.system_id=b.id where generated>? group by system_id,b.name order by b.name asc"
    connection.exec_query(sql, "SQL", [[nil, events_since.to_s(:db)]])
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

  # Shared by #hourly_stats and #events_per_hour. extract() is Postgres-only, so
  # these dashboard queries never worked against the sqlite dev/test database;
  # binding the parameters at least keeps them injection-free and consistent.
  def self.hourly_counts(system_id, since)
    sql = "select count(*) as count,extract(year from generated) as year, extract(month from generated) as month,extract(day from generated) as day, extract(hour from generated) as hour from events where events.system_id=? and events.generated>? group by year,month,day,hour order by year,month,day,hour asc"
    ActiveRecord::Base.connection.exec_query sql, "SQL", [[nil, system_id], [nil, since]]
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
    results = connection.exec_query sql, "SQL", [[nil, self.id], [nil, since]]
    return results[0]["count"].to_i
  end

  # [mean, variance, standard deviation] of this system's hourly event counts
  # since +since+. Used to spot a host that has become abnormally noisy or quiet.
  #
  # Depends on System.hourly_counts, so it is Postgres-only (extract()).
  def hourly_stats(since=1.day.ago)
      results = System.hourly_counts(self.id, since)
      values = Array.new
      results.each{|s| values << s["count"].to_i }
      mean = Math.mean(values)
      variance = Math.variance(values)
      standard_deviation = Math.standard_deviation(values)
      [mean, variance, standard_deviation]
  end

  # This system's hourly event counts since +since+ as [["M/D/YYYY H:00:00", n], ...],
  # ready to hand to a charting library. Postgres-only (see hourly_counts).
  def events_per_hour(since=7.days.ago)
    results = System.hourly_counts(self.id, since)
    data=Hash.new
    results.each{|s| data["#{s['month']}/#{s['day']}/#{s['year']} #{s['hour']}:00:00"] = s["count"].to_i}
    data.map { |k,v| ["#{k}",v] }
  end

end

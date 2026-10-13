# View helpers for the dashboard: nav highlighting, timestamp tooltips, and the
# aggregate queries behind the charts.
#
# Mixed into every view. The statistics helpers are read-only and are called
# directly from the dashboard templates; they are Postgres-only where they use
# extract().
module ApplicationHelper
  # Returns "active" or "inactive" for the nav bar, comparing the given controller
  # name against the current request. Call from a layout as class="<%%= is_active(model) %%>".
  # Note the argument is the controller name, not a path.
  def is_active(controller)       
    params[:controller] == controller ? "active" : "inactive"     
  end
  
  # Wraps +timestamp+ in a <span> whose title-style attribute lists the same instant
  # in five fixed time zones, so hovering a log time reveals it in each.
  #
  # Returns an HTML string; render it raw or it will be escaped. The zone list is
  # hard-coded -- see the array below if a deployment needs different zones.
  def timestamp_helper(timestamp=Time.now)
    timezones = [
      "Eastern Time (US & Canada)",
      "Pacific Time (US & Canada)",
      "Asia/Seoul",
      "Europe/London",
      "Asia/Shanghai"]
    tooltip = ""
    timezones.each do |zone|
      tooltip = tooltip + "#{zone}: #{timestamp.in_time_zone(zone)}\n"
    end
    span = "<span class='timestamp' time=\"#{tooltip}\">#{timestamp}</span>"
    return span
  end
  
  # Whitelist of aggregate expressions usable by #statistics_by_hour.
  # aggregate is looked up in AGGREGATES rather than interpolated, so a caller
  # can never steer the SQL text.
  AGGREGATES = { 'sum' => 'sum(stat)', 'avg' => 'avg(stat)' }.freeze

  # Single parameterized query behind the dashboard chart helpers below. The aggregate
  # is looked up in AGGREGATES rather than interpolated, so a caller can never steer
  # the SQL text.
  #
  # +type_id+ selects the series (0 = lines processed, 1 = events/sec); +agg+ must be
  # a key of AGGREGATES, anything else raises KeyError instead of reaching the
  # database. Uses extract(), so it is Postgres-only. Returns a result set with
  # agg_value/year/month/day/hour columns.
  def statistics_by_hour(type_id, since, agg = 'sum')
    aggregate = AGGREGATES.fetch(agg)
    sql = "select #{aggregate} as agg_value,extract(year from timestamp) as year, extract(month from timestamp) as month,extract(day from timestamp) as day, extract(hour from timestamp) as hour from statistics where type_id=? and timestamp>? group by year,month,day,hour order by year,month,day,hour asc"
    ActiveRecord::Base.connection.exec_query sql, "SQL", [[nil, type_id], [nil, since]]
  end

  # Lines-processed totals per hour since +since+, as [["M/D/YYYY H:00:00", n], ...]
  # in a form ready for the charting library. Postgres-only (see #statistics_by_hour).
  def events_per_hour(since=7.days.ago)
    results = statistics_by_hour(0, since)
    data=Hash.new
    results.each{|s| data["#{s['month']}/#{s['day']}/#{s['year']} #{s['hour']}:00:00"] = s['agg_value'].to_i}
    data.map { |k,v| ["#{k}",v] }
  end
  
  # Average insert rate per hour since +since+, as [["M/D/YYYY H:00:00", rate], ...].
  # Averages rather than sums, because the underlying samples are already rates.
  def inserts_per_second(since=1.day.ago)
    results = statistics_by_hour(1, since, 'avg')
    data=Hash.new
    results.each{|s| data["#{s['month']}/#{s['day']}/#{s['year']} #{s['hour']}:00:00"] = s['agg_value'].to_f}
    data.map { |k,v| ["#{k}",v] }
  end
  
  # Event counts per host over the last +days+ days, keyed by System#display_name.
  # Issues one lookup per system_id, so it is O(number of reporting hosts).
  def system_stats(days)
    counts = Event.where("generated > ?", (Time.now()-(days * 86400)).to_s(:db)).group(:system_id).count
    results = Hash.new
    counts.each do |system_id, count|
      results[System.find(system_id).display_name] = count
    end
    results.map { |k,v| [k,v] }
  end
  
  # Event counts per service over the last +days+ days.
  #
  # Returns a *string* (the array's #inspect) rather than the array itself, because
  # the chart is fed by an inline script tag. Note it calls Service.find on every
  # service_id, so a nil service_id raises.
  def service_stats(days)
    counts = Event.where("generated > ?", (Time.now()-(days*86400)).to_s(:db)).group(:service_id).count
    results = Hash.new
    counts.each do |service_id, count|
      results[Service.find(service_id).name] = count
    end
    (results.map { |k,v| [k,v] }).inspect
  end  
  
  # Number of events generated after +time_frame+. Exact COUNT(*), so it is expensive
  # on a large table -- prefer Event.approximate_count for the headline figure.
  def total_events_since(time_frame)
    Event.where("generated > ?",time_frame).count
  end
  
  # Root-filesystem usage as a two-slice pie chart, [["Used", n], ["Free", 100-n]].
  # Returns a string for an inline script tag; delegates to Event.diskUtilization,
  # which shells out to df.
  def disk_utilization()
    used = Event.diskUtilization
    free = 100 - used
    "[[\"Used\", #{used}],[\"Free\", #{free}]]"
  end
  
  # Mean of the hourly event totals since +since+. Returns NaN when there are no
  # samples (Math.mean divides by an empty count).
  def hourly_average(since=1.day.ago)
      results = statistics_by_hour(0, since)
      values = Array.new
      results.each{|s| values << s['agg_value'].to_i }
      Math.mean(values)
  end

  # [mean, variance, standard deviation] of the hourly event totals since +since+,
  # for the dashboard's baseline-vs-anomaly display.
  def hourly_stats(since=1.day.ago)
      results = statistics_by_hour(0, since)
      values = Array.new
      results.each{|s| values << s['agg_value'].to_i }
      mean = Math.mean(values)
      variance = Math.variance(values)
      standard_deviation = Math.standard_deviation(values)
      [mean, variance, standard_deviation]
  end
  

  # Mean hourly insert rate since +since+, converted to a per-second figure by
  # dividing by 60.
  def daily_insert_average(since=1.day.ago)
      results = statistics_by_hour(1, since)
      values = Array.new
      results.each{|s| values << s['agg_value'].to_i }
      
      Math.mean(values) / 60.0
  end
end

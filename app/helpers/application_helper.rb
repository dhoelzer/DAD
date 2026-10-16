# View helpers for the dashboard: nav highlighting, timestamp tooltips, and the
# aggregate queries behind the charts.
#
# Mixed into every view. The statistics helpers are read-only and are called
# directly from the dashboard templates. Their SQL is portable across Postgres
# (production) and SQLite (test/dev) so the dashboard renders under both.
module ApplicationHelper
  # Returns "active" or "inactive" for the nav bar, comparing the given controller
  # name against the current request. Call from a layout as class="<%%= is_active(model) %%>".
  # Note the argument is the controller name, not a path.
  def is_active(controller)       
    params[:controller] == controller ? "active" : "inactive"     
  end
  
  # Emits +value+ as a JavaScript literal for a .js.erb template.
  #
  # Needed because Rails HTML-escapes <%= %> in a JS template (see
  # ErubiHandler.escape_whitelist, which covers text/plain only). HTML escaping
  # neutralises a quote but leaves a backslash alone, so a value ending in "\"
  # silently corrupts the generated script. to_json produces a real JS literal;
  # json_escape additionally turns < > & into \uXXXX so the value cannot
  # terminate a surrounding <script> tag if the template is ever inlined.
  #
  # Do not use for values that may be NaN: JSON has no NaN, so to_json emits
  # null and the arithmetic changes. Those stay as plain numeric interpolation.
  def js_literal(value)
    ERB::Util.json_escape(value.to_json).html_safe
  end

  # Wraps +timestamp+ in a <span> whose time attribute lists the same instant
  # in five fixed time zones, so hovering a log time reveals it in each.
  #
  # Built with content_tag so the result is html_safe by construction and call
  # sites need no raw. The zone list is hard-coded -- see the array below if a
  # deployment needs different zones.
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
    content_tag :span, timestamp, class: "timestamp", time: tooltip
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
  # database. Returns a result set with agg_value/bucket columns, where bucket is the
  # hour as "YYYY-MM-DD HH".
  #
  # The bucket is built with substr(cast(<ts> as text), 1, 13) rather than
  # extract(), because extract() is Postgres-only and SQLite rejects it outright.
  # Both engines render a timestamp as "YYYY-MM-DD HH:MM:SS[.ffffff]", so the first
  # 13 characters name the hour on either one. Keeping the query portable is what
  # lets the dashboard render under the sqlite test suite at all.
  def statistics_by_hour(type_id, since, agg = 'sum')
    aggregate = AGGREGATES.fetch(agg)
    sql = "select #{aggregate} as agg_value,substr(cast(timestamp as text),1,13) as bucket from statistics where type_id=? and timestamp>? group by bucket order by bucket asc"
    SqlPlaceholders.query sql, [type_id, since]
  end

  # The bucketed rows behind every chart helper, as [["YYYY-MM-DD HH", value], ...].
  #
  # The helpers below reduce this in Ruby rather than each issuing their own query,
  # so a page that needs several views of one series fetches it once.
  def hourly_buckets(type_id, since, agg = 'sum')
    statistics_by_hour(type_id, since, agg).map { |row| [row['bucket'], row['agg_value']] }
  end

  # Lines-processed totals per hour since +since+, as [["M/D/YYYY H:00:00", n], ...]
  # in a form ready for the charting library.
  def events_per_hour(since=7.days.ago)
    BucketStats.series(hourly_buckets(0, since))
  end

  # Average insert rate per hour since +since+, as [["M/D/YYYY H:00:00", rate], ...].
  # Averages rather than sums, because the underlying samples are already rates.
  def inserts_per_second(since=1.day.ago)
    data = Hash.new
    hourly_buckets(1, since, 'avg').each do |bucket, value|
      data[ApplicationHelper.chart_label(bucket)] = value.to_f
    end
    data.map { |label, value| [label, value] }
  end

  # Turns an "YYYY-MM-DD HH" bucket into the "M/D/YYYY H:00:00" label the charts
  # expect, dropping the zero padding the database adds. A module function so the
  # models that build the same labels can call it without including this module.
  def self.chart_label(bucket)
    time = DateTime.parse("#{bucket}:00")
    "#{time.month}/#{time.day}/#{time.year} #{time.hour}:00:00"
  end
  
  # Event counts per host over the last +days+ days, as [["display name", n], ...].
  #
  # One grouped query plus one lookup for all the systems, rather than a
  # System.find per group. Keyed by id instead of display name: two hosts with
  # the same display name used to collapse into one entry, silently dropping a
  # count.
  def system_stats(days)
    counts = Event.where("generated > ?", (Time.now()-(days * 86400)).to_fs(:db)).group(:system_id).count
    systems = System.where(id: counts.keys).index_by(&:id)
    counts.map { |system_id, count| [systems.fetch(system_id).display_name, count] }
  end
  
  # Event counts per service over the last +days+ days, as [["name", n], ...].
  #
  # Returns the array, not #inspect: the chart consumes it through #js_literal,
  # which emits a real JS literal. Ruby's #inspect is not a JavaScript escaper
  # and the service names arrive from syslog. A nil service_id still has no
  # Service row to resolve, so it raises rather than rendering a blank label.
  def service_stats(days)
    counts = Event.where("generated > ?", (Time.now()-(days*86400)).to_fs(:db)).group(:service_id).count
    services = Service.where(id: counts.keys).index_by(&:id)
    counts.map { |service_id, count| [services.fetch(service_id).name, count] }
  end  
  
  # Number of events generated after +time_frame+. Exact COUNT(*), so it is expensive
  # on a large table -- prefer Event.approximate_count for the headline figure.
  def total_events_since(time_frame)
    Event.where("generated > ?",time_frame).count
  end
  
  # Usage of the partition holding the event archives, as a two-slice pie chart,
  # [["Used", n], ["Free", 100-n]]. Delegates to Event.diskUtilization; render
  # the result through #js_literal.
  #
  # Returns nil when the filesystem cannot be measured, so the caller skips the
  # chart rather than drawing a 0%-used pie for a disk that may be full.
  def disk_utilization()
    used = Event.diskUtilization
    return nil if used.nil?
    [["Used", used], ["Free", 100 - used]]
  end
  
  # [mean, variance, standard deviation] of the hourly event totals since +since+,
  # for the dashboard's baseline-vs-anomaly display.
  def hourly_stats(since=1.day.ago)
    BucketStats.summary(hourly_buckets(0, since))
  end

  # Mean hourly insert rate since +since+, converted to a per-second figure by
  # dividing by 60.
  #
  # Averages the 'sum' aggregate, preserving the pre-existing behaviour. The type_id
  # 1 samples are already per-second rates, so 'avg' is arguably the right
  # aggregate, but switching it would change the number on the gauge; that is a
  # behaviour change rather than a refactor, so it is left for a separate decision.
  def daily_insert_average(since=1.day.ago)
    Stats.mean(hourly_buckets(1, since).map { |_, value| value.to_i }) / 60.0
  end
end

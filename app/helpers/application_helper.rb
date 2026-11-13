# View helpers for the dashboard: nav highlighting, timestamp tooltips, and the
# aggregate queries behind the charts.
#
# Mixed into every view. The statistics helpers are read-only and are called
# directly from the dashboard templates. Their SQL is portable across Postgres
# (production, development and test) so the dashboard renders everywhere.
module ApplicationHelper
  # Nav bar order and labels. The bar used to be `$_models.sort`, so tab order was
  # alphabetical by class name and every label was the class name itself --
  # "ActiveDirectoryConnection" and "WindowsTarget" rendered in full at 120px each.
  # Order and labels are declared here; the models still decide *whether* a tab
  # appears, through hidden?.
  #
  # The first four are the everyday path: events, then search, then the two
  # host-shaped indexes. Windows groups the two setup screens -- the directory
  # connection and the polled-host list -- under one dropdown, because they are
  # configured occasionally rather than viewed daily.
  NAV_PRIMARY = %w[Event Search System Service].freeze

  # Moved under the "Windows" dropdown and hidden from the flat list.
  NAV_WINDOWS = %w[ActiveDirectoryConnection WindowsTarget].freeze

  # Short labels for the two dropdown entries. The class names were the old tab
  # labels, and at 120px per tab "ActiveDirectoryConnection" does not fit.
  NAV_LABELS = { 'ActiveDirectoryConnection' => 'AD',
                 'WindowsTarget' => 'Windows' }.freeze

  def nav_label(model)
    NAV_LABELS.fetch(model, model)
  end

  # Visible models in nav order: the four primary tabs, then everything else in
  # $_models order. NAV_WINDOWS is excluded here because it renders in the
  # dropdown; a model that is hidden? for this user gets no tab anywhere.
  def nav_flat_models
    ordered = NAV_PRIMARY + ($_models - NAV_PRIMARY - NAV_WINDOWS)
    ordered.select do |model|
      !model.include?('HABTM') && !model.constantize.hidden?(@current_user)
    end
  end

  def nav_windows_models
    NAV_WINDOWS.select { |model| !model.constantize.hidden?(@current_user) }
  end

  # Class for the dropdown's own <li>. Deliberately *not* "active": the nav bar
  # guarantees exactly one li.active per page (asserted in unique_ids_test), and
  # marking both the group and its open child active would render two. The group
  # gets its own hook so it can still be highlighted while a child is current.
  def nav_group_class(models)
    paths = models.map { |model| nav_controller_path(model) }
    paths.include?(params[:controller]) ? "group-active" : "group-inactive"
  end

  # Controller path a model's tab points at, i.e. the value of params[:controller]
  # when that page renders.
  #
  # tableize, not pluralize.downcase: the old layout used the latter, which yields
  # "windowstargets" and "activedirectoryconnections" where the real controller
  # paths are "windows_targets" and "active_directory_connections". Those two tabs
  # never received class="active", so the highlight silently lied on every
  # Windows screen.
  def nav_controller_path(model)
    model.tableize
  end

  # Returns "active" or "inactive" for the nav bar. Takes a model name, because
  # that is what the layout iterates; nav_controller_path turns it into the
  # controller path the current request reports.
  def is_active(model)
    params[:controller] == nav_controller_path(model) ? "active" : "inactive"
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
  # extract(). extract() is engine-specific and broke the dashboard everywhere
  # the suite ran, because the suite ran a different engine; substr over the
  # rendered "YYYY-MM-DD HH:MM:SS[.ffffff]" form names the hour in its first 13
  # characters and needs no adapter branch.
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

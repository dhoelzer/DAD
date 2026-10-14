# View helpers for the per-host detail page.
module SystemsHelper
  
  # Event counts per service for one host, as [["service", n], ...] rendered through
  # ApplicationHelper#js_literal. Service names arrive from syslog, so this must not
  # be #inspect'd into the script. Unbounded: counts every event ever recorded for
  # that host, not a time window.
  def system_service_stats(system_id)
    counts = Event.where(:system_id => system_id).group(:service_id).count
    results = Hash.new
    counts.each do |service_id, count|
      results[Service.find(service_id).name] = count
    end
    results.map { |k,v| [k,v] }
  end
  
end

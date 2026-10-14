# View helpers for the per-host detail page.
module SystemsHelper
  
  # Event counts per service for one host, as [["service", n], ...] rendered through
  # ApplicationHelper#js_literal. Service names arrive from syslog, so this must not
  # be #inspect'd into the script. Unbounded: counts every event ever recorded for
  # that host, not a time window.
  #
  # One grouped query plus one lookup for all the services, rather than a
  # Service.find per group. Keyed by id, matching ApplicationHelper#service_stats.
  def system_service_stats(system_id)
    counts = Event.where(:system_id => system_id).group(:service_id).count
    services = Service.where(id: counts.keys).index_by(&:id)
    counts.map { |service_id, count| [services.fetch(service_id).name, count] }
  end
  
end

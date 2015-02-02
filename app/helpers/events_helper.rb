module EventsHelper
  def system_stats(days)
    counts = Event.where("generated > NOW()-'? day'::interval", days).group(:system_id).count
    results = Hash.new
    counts.each do |system_id, count|
      results[System.find(system_id).display_name] = count
    end
    results.map { |k,v| [k,v] }
  end
  
  def service_stats(days)
    counts = Event.where("generated > NOW()-'? day'::interval", days).group(:service_id).count
    results = Hash.new
    counts.each do |service_id, count|
      results[Service.find(service_id).name] = count
    end
    (results.map { |k,v| [k,v] }).inspect
  end  
  
  def total_events_since(time_frame)
    Event.where("generated > ?",time_frame).count
  end
  
  def daily_average
    return 1000000
    first = Event.order(:generated).first.generated
    last = Event.order(:generated).last.generated
    total = Event.count
    total / ((last - first) / (60*60*24))
  end
end

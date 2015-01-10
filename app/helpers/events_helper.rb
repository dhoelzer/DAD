module EventsHelper
  def system_stats
    counts = Event.group(:system_id).count
    results = Hash.new
    counts.each do |system_id, count|
      results[System.find(system_id).name] = count
    end
    results.map { |k,v| [k,v] }
  end
  
  def service_stats
    counts = Event.group(:service_id).count
    results = Hash.new
    counts.each do |service_id, count|
      results[Service.find(service_id).name] = count
    end
    (results.map { |k,v| [k,v] }).inspect
  end  
end

module SystemsHelper
  
  def system_service_stats(system_id)
    counts = Event.where(:system_id => system_id).group(:service_id).count
    results = Hash.new
    counts.each do |service_id, count|
      results[Service.find(service_id).name] = count
    end
    (results.map { |k,v| [k,v] }).inspect
  end
  
end

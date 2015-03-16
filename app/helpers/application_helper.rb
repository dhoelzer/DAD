module ApplicationHelper
  def is_active(controller)       
    puts "#{controller} -> #{params[:controller]}"
    params[:controller] == controller ? "active" : "inactive"     
  end
  
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
  
  def events_per_hour(since=7.days.ago)
    connection = ActiveRecord::Base.connection    
    sql = "select sum(stat),extract(year from timestamp) as year, extract(month from timestamp) as month,extract(day from timestamp) as day, extract(hour from timestamp) as hour from statistics where type_id=0 and timestamp>'#{since}' group by year,month,day,hour order by year,month,day,hour asc"
    results = connection.execute sql
    data=Hash.new
    results.each{|s| data["#{s['month']}/#{s['day']}/#{s['year']} #{s['hour']}:00:00"] = s['sum'].to_i}
    data.map { |k,v| ["#{k}",v] }
  end
  
  def inserts_per_second(since=1.day.ago)
    connection = ActiveRecord::Base.connection    
    sql = "select avg(stat),extract(year from timestamp) as year, extract(month from timestamp) as month,extract(day from timestamp) as day, extract(hour from timestamp) as hour from statistics where type_id=1 and timestamp>'#{since}' group by year,month,day,hour order by year,month,day,hour asc"
    results = connection.execute sql
    data=Hash.new
    results.each{|s| data["#{s['month']}/#{s['day']}/#{s['year']} #{s['hour']}:00:00"] = s['avg'].to_f}
    data.map { |k,v| ["#{k}",v] }
  end
  
  def system_stats(days)
    counts = Event.where("generated > ?", Time.now()-(days * 86400)).group(:system_id).count
    results = Hash.new
    counts.each do |system_id, count|
      results[System.find(system_id).display_name] = count
    end
    results.map { |k,v| [k,v] }
  end
  
  def service_stats(days)
    counts = Event.where("generated > ?", Time.now()-(days*86400)).group(:service_id).count
    results = Hash.new
    counts.each do |service_id, count|
      results[Service.find(service_id).name] = count
    end
    (results.map { |k,v| [k,v] }).inspect
  end  
  
  def total_events_since(time_frame)
    Event.where("generated > ?",time_frame).count
  end
  
  def disk_utilization()
    used = Event.diskUtilization
    free = 100 - used
    "[[\"Used\", #{used}],[\"Free\", #{free}]]"
  end
  
  def hourly_average(since=1.day.ago)
      connection = ActiveRecord::Base.connection    
      sql = "select sum(stat),extract(year from timestamp) as year, extract(month from timestamp) as month,extract(day from timestamp) as day, extract(hour from timestamp) as hour from statistics where type_id=0 and timestamp>'#{since}' group by year,month,day,hour order by year,month,day,hour asc"
      results = connection.execute sql
      values = Array.new
      results.each{|s| values << s['sum'].to_i }
      Math.mean(values)
  end

  def hourly_stats(since=1.day.ago)
      connection = ActiveRecord::Base.connection    
      sql = "select sum(stat),extract(year from timestamp) as year, extract(month from timestamp) as month,extract(day from timestamp) as day, extract(hour from timestamp) as hour from statistics where type_id=0 and timestamp>'#{since}' group by year,month,day,hour order by year,month,day,hour asc"
      results = connection.execute sql
      values = Array.new
      results.each{|s| values << s['sum'].to_i }
      mean = Math.mean(values)
      variance = Math.variance(values)
      standard_deviation = Math.standard_deviation(values)
      [mean, variance, standard_deviation]
  end
  

  def daily_insert_average(since=1.day.ago)
      connection = ActiveRecord::Base.connection    
      sql = "select sum(stat),extract(year from timestamp) as year, extract(month from timestamp) as month,extract(day from timestamp) as day, extract(hour from timestamp) as hour from statistics where type_id=1 and timestamp>'#{since}' group by year,month,day,hour order by year,month,day,hour asc"
      results = connection.execute sql
      values = Array.new
      results.each{|s| values << s['sum'].to_i }
      
      Math.mean(values) / 60.0
  end
end

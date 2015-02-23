module EventsHelper
  
  def events_per_hour(since=7.days.ago)
    connection = ActiveRecord::Base.connection    
    sql = "select sum(stat),extract(year from timestamp) as year, extract(month from timestamp) as month,extract(day from timestamp) as day, extract(hour from timestamp) as hour from statistics where type_id=0 group by year,month,day,hour order by year,month,day,hour asc"
    results = connection.execute sql
    data=Hash.new
    results.each{|s| data["#{s['month']}/#{s['day']}/#{s['year']} #{s['hour']}:00:00"] = s['sum'].to_i}
    data.map { |k,v| ["#{k}",v] }
  end
  
  def inserts_per_second(since=1.day.ago)
    connection = ActiveRecord::Base.connection    
    sql = "select avg(stat),extract(year from timestamp) as year, extract(month from timestamp) as month,extract(day from timestamp) as day, extract(hour from timestamp) as hour from statistics where type_id=1 group by year,month,day,hour order by year,month,day,hour asc"
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
  
  def daily_average
      connection = ActiveRecord::Base.connection    
      sql = "select sum(stat),extract(year from timestamp) as year, extract(month from timestamp) as month,extract(day from timestamp) as day from statistics where type_id=1 group by year,month,day order by year,month,day asc"
      results = connection.execute sql
      data=Hash.new
      sum = 0
      results.each{|s| sum = sum + s['sum'].to_i}
      sum.to_f / (results.count * 24)
  end

  def daily_insert_average
      connection = ActiveRecord::Base.connection    
      sql = "select avg(stat),extract(year from timestamp) as year, extract(month from timestamp) as month,extract(day from timestamp) as day from statistics where type_id=0 group by year,month,day order by year,month,day asc"
      results = connection.execute sql
      data=Hash.new
      sum = 0
      results.each{|s| sum = sum + s['avg'].to_i}
      sum.to_f / results.count
  end

end

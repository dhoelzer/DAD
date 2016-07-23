class System < ActiveRecord::Base
  has_many :events
  has_many :services, :through => :events
  
  @@cached_stuff = Hash.new
  @added = 0
  
  def self.hidden?(current_user = nil)
    return true if current_user.nil?
    return true unless current_user.has_right?("Viewer")
    return false
  end
  
  def self.with_events_within_hours(hours=1)
    counts = Event.where("generated > ?", (Time.now()-(hours * 3600)).to_s(:db)).group(:system_id).count
    results = Array.new
    counts.each do |system_id, count|
      results << System.find(system_id) unless count <= 0
    end
    return results
  end
  
  def self.reportingInLastDays(days)
    connection = ActiveRecord::Base.connection
    events_since = (Time.now - (days * 86400))
    sql = "select system_id,b.name,count(*) from events as a join systems as b on  a.system_id=b.id where generated>'#{events_since.to_s(:db)}' group by system_id,b.name order by b.name asc"
    connection.execute(sql)    
  end
  
  def display_name
    return "(#{self.address})" if self.name.nil?
    "#{self.name}"
  end
  
  def self.find_or_add(new_item)
    return @@cached_stuff[new_item] if @@cached_stuff.has_key?(new_item)
    item=System.find_by address: new_item
    if item.nil? then
      item = System.create(:address => new_item)
      @added += 1
    end
    @@cached_stuff[new_item] = item
    return item
  end
  
  def self.number_of_cached_items
    return @@cached_stuff.size
  end
  
  def self.added
    return @added
  end
  
  def events_since(since=1.hour.ago)
    connection = ActiveRecord::Base.connection    
    sql = "select count(*) from events where events.system_id=#{self.id} and generated>'#{since}'"
    results = connection.execute sql
    return results[0]["count"].to_i
  end
  
  def hourly_stats(since=1.day.ago)
      connection = ActiveRecord::Base.connection    
      sql = "select count(*),extract(year from generated) as year, extract(month from generated) as month,extract(day from generated) as day, extract(hour from generated) as hour from events where events.system_id=#{self.id} and events.generated>'#{since}' group by year,month,day,hour order by year,month,day,hour asc"
      results = connection.execute sql
      values = Array.new
      results.each{|s| values << s["count"].to_i }
      mean = Math.mean(values)
      variance = Math.variance(values)
      standard_deviation = Math.standard_deviation(values)
      [mean, variance, standard_deviation]
  end
  
  def events_per_hour(since=7.days.ago)
    connection = ActiveRecord::Base.connection    
    sql = "select count(*),extract(year from generated) as year, extract(month from generated) as month,extract(day from generated) as day, extract(hour from generated) as hour from events where events.system_id=#{self.id} and events.generated>'#{since}' group by year,month,day,hour order by year,month,day,hour asc"
    results = connection.execute sql
    data=Hash.new
    results.each{|s| data["#{s['month']}/#{s['day']}/#{s['year']} #{s['hour']}:00:00"] = s["count"].to_i}
    data.map { |k,v| ["#{k}",v] }
  end
  
end

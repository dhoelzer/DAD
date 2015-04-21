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
  
  def self.reportingInLastDays(days)
    connection = ActiveRecord::Base.connection
    time_interval = Time.now - (days * 86400)
    sql = "select system_id,b.name,count(*) from events as a join systems as b on  a.system_id=b.id where generated>'#{time_interval}' group by system_id,b.name order by b.name asc"
    connection.execute(sql)    
  end
  
  def display_name
    return "(#{self.address})" if self.name.nil?
    "#{self.name}(#{self.address})"
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
    sql = "select count(*) from events where system_id=#{self.id} and generated>'#{since}'"
    results = connection.execute sql
    values = Array.new
    results.each{|s| values << s[0].to_i }
    return values[0]
  end
  
  def hourly_stats(since=1.day.ago)
      connection = ActiveRecord::Base.connection    
      sql = "select count(*),extract(year from generated) as year, extract(month from generated) as month,extract(day from generated) as day, extract(hour from generated) as hour from events where system_id=#{self.id} and generated>'#{since}' group by year,month,day,hour order by year,month,day,hour asc"
      results = connection.execute sql
      values = Array.new
      results.each{|s| values << s[0].to_i }
      mean = Math.mean(values)
      variance = Math.variance(values)
      standard_deviation = Math.standard_deviation(values)
      [mean, variance, standard_deviation]
  end
  
  def events_per_hour(since=7.days.ago)
    connection = ActiveRecord::Base.connection    
    sql = "select count(*),extract(year from generated) as year, extract(month from generated) as month,extract(day from generated) as day, extract(hour from generated) as hour from events where system_id=#{self.id} and generated>'#{since}' group by year,month,day,hour order by year,month,day,hour asc"
    results = connection.execute sql
    data=Hash.new
    results.each{|s| data["#{s[2]}/#{s[3]}/#{s[1]} #{s[4]}:00:00"] = s[0].to_i}
    data.map { |k,v| ["#{k}",v] }
  end
  
end

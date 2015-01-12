class System < ActiveRecord::Base
  has_many :events
  has_many :services, :through => :events
  
  @@cached_stuff = Hash.new
  @added = 0
  
  def display_name
    return self.name if self.description.nil?
    "#{self.name}(#{self.description})"
  end
  
  def self.find_or_add(new_item)
    return @@cached_stuff[new_item] if @@cached_stuff.has_key?(new_item)
    item=System.find_by name: new_item
    if item.nil? then
      item = System.create(:name => new_item)
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
end

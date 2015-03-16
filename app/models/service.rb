class Service < ActiveRecord::Base
  has_many :events
  has_many :servers, :through => :events
  
  @@cached_stuff = Hash.new
  @added = 0
  
  def self.hidden?(current_user = nil)
    return true if current_user.nil?
    return true unless current_user.has_right?("Viewer")
    return false
  end
  
  
  def self.find_or_add(new_item)
    return @@cached_stuff[new_item] if @@cached_stuff.has_key?(new_item)
    item=Service.find_by name: new_item
    if item.nil? then
      item = Service.create(:name => new_item)
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

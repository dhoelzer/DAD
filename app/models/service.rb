class Service < ActiveRecord::Base
  has_many :events
  has_many :servers, :through => :events
  
  @@cached_stuff = GoogleHashSparseRubyToRuby.new
  @added = 0
  
  def self.find_or_add(new_item)
    return @@cached_stuff[new_item] if @@cached_stuff.keys.include?(new_item)
    item=Service.find_by name: new_item
    if item.nil? then
      item = Service.create(:name => new_item)
      @added += 1
    end
    @@cached_stuff[new_item] = item
    return item
  end
  
  def self.number_of_cached_items
    return @@cached_stuff.keys.size
  end
  
  def self.added
    return @added
  end
end

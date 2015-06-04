class Display < ActiveRecord::Base
  has_many :display_fields
  
  def self.hidden?(current_user = nil)
    return true if current_user.nil?
    return true unless current_user.has_right?("Detective")
    return false
  end
  
  def self.helper_for_event(event_string)
    Display.all.each do |filter|
      begin
        reg = Regexp.new(filter.key)
        return filter unless reg.match(event_string).nil?
      rescue
        puts "Had to rescue: #{filter.key}"
        # Likely don't have enough fields.  Don't care to figure it out for now.
      end
    end
    return nil
  end
    
end

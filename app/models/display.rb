class Display < ActiveRecord::Base
  has_many :display_fields
  
  def self.hidden?(current_user = nil)
    return true if current_user.nil?
    return true unless current_user.has_right?("Analyst")
    return false
  end
  
  def self.helper_for_event(event_fields)
    Display.all.each do |filter|
      begin
        puts "filter: >#{filter.key}< #{filter.key_field} -> #{event_fields} -> >#{event_fields[filter.key_field]}<"
        return filter if event_fields[filter.key_field] == filter.key
      rescue
        puts "Had to rescue: #{filter.key} #{filter.key_field} -> #{event_fields}"
        # Likely don't have enough fields.  Don't care to figure it out for now.
      end
    end
    return nil
  end
    
end

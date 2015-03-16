class DisplayField < ActiveRecord::Base
  belongs_to :display
  
  def self.hidden?(current_user = nil)
    return true
  end
  
  
end

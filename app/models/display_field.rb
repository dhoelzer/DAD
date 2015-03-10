class DisplayField < ActiveRecord::Base
  belongs_to :display
  
  def self.hidden?
    return false
  end
  
  
end

class Position < ActiveRecord::Base
  belongs_to :event
  belongs_to :word
  
  def self.hidden?(current_user = nil)
    return true
  end
  
end

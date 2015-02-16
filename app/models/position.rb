class Position < ActiveRecord::Base
  belongs_to :event
  belongs_to :word
  
  def self.hidden?
    return true
  end
  
end

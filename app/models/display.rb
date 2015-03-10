class Display < ActiveRecord::Base
  has_many :fields
  
  def self.hidden?
    return false
  end
  
  
end

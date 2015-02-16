class Comment < ActiveRecord::Base
  belongs_to :alert
  
  def self.hidden?
    return true
  end
end

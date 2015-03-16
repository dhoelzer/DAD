class Comment < ActiveRecord::Base
  belongs_to :alert
  
  def self.hidden?(current_user = nil)
    return true
  end
end

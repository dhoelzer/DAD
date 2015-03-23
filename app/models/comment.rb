class Comment < ActiveRecord::Base
  belongs_to :alert
  belongs_to :user
  
  def self.hidden?(current_user = nil)
    return true
  end
end

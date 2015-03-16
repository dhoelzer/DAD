class Session < ActiveRecord::Base
  belongs_to :user

  def self.hidden?(current_user = nil)
    return true
  end
  
end

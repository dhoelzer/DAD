class Right < ActiveRecord::Base
  has_and_belongs_to_many :roles
  has_many :users, through: :roles
  
  def self.hidden?(current_user = nil)
    return true
  end
end

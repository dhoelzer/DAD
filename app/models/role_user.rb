class RoleUser < ActiveRecord::Base
  def self.hidden?(current_user = nil)
    return true
  end
end

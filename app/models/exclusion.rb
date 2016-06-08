class Exclusion < ActiveRecord::Base
	belongs_to :user

  def self.hidden?(current_user = nil)
    return true if current_user.nil?
    return true unless current_user.has_right?("Commentator")
    return false
  end

end

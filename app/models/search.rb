class Search < ActiveRecord::Base
  def self.hidden?(current_user = nil)
    return true if current_user.nil?
    return true unless current_user.has_right?("Detective")
    return false
  end
  
end

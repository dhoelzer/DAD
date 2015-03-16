class Role < ActiveRecord::Base
  has_and_belongs_to_many :rights
  has_and_belongs_to_many :users

  def self.hidden?(current_user = nil)
    return true if current_user.nil?
    return true unless current_user.has_right?("Admin")
    return false
  end
    
  def ungranted_rights
    return Right.all - self.rights
  end
  
  def has_right?(right)
    self.rights.include?(right)
  end
end

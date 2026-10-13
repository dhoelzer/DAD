# A named bundle of Rights assigned to Users.
#
# Users gain rights only through roles, so this is the layer an administrator
# edits when granting access.
class Role < ActiveRecord::Base
  has_and_belongs_to_many :rights
  has_and_belongs_to_many :users

  # Show the "Roles" tab only to users holding the Admin right.
  def self.hidden?(current_user = nil)
    return true if current_user.nil?
    return true unless current_user.has_right?("Admin")
    return false
  end

  # Rights this role does not yet hold -- the candidate list for the grant form.
  def ungranted_rights
    return Right.all - self.rights
  end

  # True if this role holds +right+ (a Right record).
  #
  # Unlike User#has_right?, this does not treat Admin as a wildcard; it is a
  # plain membership test used by RolesController#right_add/#right_remove.
  def has_right?(right)
    self.rights.include?(right)
  end
end

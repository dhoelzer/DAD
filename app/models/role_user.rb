# Join model for the users<->roles many-to-many relationship.
#
# As with RightRole, the real association is has_and_belongs_to_many on User and
# Role; this class is only picked up by the nav-bar model enumeration.
class RoleUser < ActiveRecord::Base
  # Internal join table: never shown in the navigation bar.
  def self.hidden?(current_user = nil)
    return true
  end
end

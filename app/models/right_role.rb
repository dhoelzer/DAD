# Join model for the roles<->rights many-to-many relationship.
#
# The relationship is actually declared with has_and_belongs_to_many on Role and
# Right, so this class exists only to satisfy the nav-bar enumeration over
# ActiveRecord subclasses; it is not used for queries.
class RightRole < ActiveRecord::Base
  # Internal join table: never shown in the navigation bar.
  def self.hidden?(current_user = nil)
    return true
  end
end

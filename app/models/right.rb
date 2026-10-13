# A named permission ("Viewer", "Commentator", "Detective", "Taskmaster",
# "Admin") checked by User#has_right? and by every controller's authorized?.
class Right < ActiveRecord::Base
  has_and_belongs_to_many :roles
  has_many :users, through: :roles

  # Rights are managed from the Roles screens; the standalone tab is hidden.
  def self.hidden?(current_user = nil)
    return true
  end
end

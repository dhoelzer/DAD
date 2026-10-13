# A user-authored note attached to an Alert.
#
# Created from CommentsController#create, which stamps user_id from the
# logged-in session rather than trusting params.
class Comment < ActiveRecord::Base
  belongs_to :alert
  belongs_to :user

  # Comments have no index page of their own -- they are only rendered inside an
  # Alert's show view -- so the "Comments" tab stays hidden for every user.
  def self.hidden?(current_user = nil)
    return true
  end
end

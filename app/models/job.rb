# A scheduled Ruby snippet, re-run on a fixed interval by scheduler.rb.
#
# The scheduler evaluates Job#script with Kernel#eval every Job#frequency seconds
# once Job#next_run is in the past, and raises an Alert on failure. Because the
# script is stored and eval'd, creating a Job is equivalent to remote code
# execution on the host -- restrict the Taskmaster right accordingly.
class Job < ActiveRecord::Base
  belongs_to :user

  # Show the "Jobs" tab only to users holding the Taskmaster right.
  def self.hidden?(current_user = nil)
    return true if current_user.nil?
    return true unless current_user.has_right?("Taskmaster")
    return false
  end
end

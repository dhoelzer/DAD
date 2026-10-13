# A scheduled task, re-run on a fixed interval by scheduler.rb.
#
# Job#script names an entry in the JobHandler::HANDLERS registry; the scheduler
# looks the name up and calls it every Job#frequency seconds once Job#next_run is
# in the past, raising an Alert on failure. Creating a Job can therefore only
# select from a fixed, code-defined set of operations.
class Job < ActiveRecord::Base
  belongs_to :user

  validate :script_names_a_handler

  # Rejects a Job whose script is not a registered handler name. This is the
  # boundary that replaced eval: an unrecognised name never reaches the runtime.
  def script_names_a_handler
    return if script.blank?
    unless JobHandler.known?(script)
      errors.add(:script, "must be one of: #{JobHandler.names.join(', ')}")
    end
  end

  # Show the "Jobs" tab only to users holding the Taskmaster right.
  def self.hidden?(current_user = nil)
    return true if current_user.nil?
    return true unless current_user.has_right?("Taskmaster")
    return false
  end
end

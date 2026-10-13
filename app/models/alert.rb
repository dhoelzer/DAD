# An operational finding raised against a System (optionally a Service), with a
# syslog-style criticality and an open/closed state.
#
# Alerts are created three ways: by hand through AlertsController, by
# Alert.hostUnreachable when a System stops reporting, and by Alert.genericAlert
# (used by scheduler.rb when a Job raises). Comments attach to alerts, and
# events can be linked to them through the events_alerts join table.
class Alert < ActiveRecord::Base
  has_and_belongs_to_many :events
  has_many :comments
  belongs_to :system
  belongs_to :service

  # Show the "Alerts" tab only to users holding the Viewer right.
  def self.hidden?(current_user = nil)
    return true if current_user.nil?
    return true unless current_user.has_right?("Viewer")
    return false
  end

  # Human-readable label for the integer +criticality+ (0=Debug .. 5=Critical).
  #
  # Note the comparison against the *string* "4" for Serious: a criticality
  # stored as the integer 4 falls through to "Critical" instead. Callers that
  # write criticality should store integers 0-5 and treat 4 as Critical, or fix
  # the comparison.
  def criticality_name
    self.criticality == 0 ? "Debug" : self.criticality == 1 ? "Informational" : self.criticality == 2 ? "Warning" : self.criticality == 3 ? "Important" : self.criticality == "4" ? "Serious" : "Critical"
  end

  # Raises a Critical alert stating that +system+ has stopped sending events.
  #
  # Called from the dashboard when a System has no events within the lookback
  # window. The alert is left open (closed = false) for an operator to
  # acknowledge.
  def self.hostUnreachable(system)
    alert=Alert.new
    alert.system_id = system.id
    alert.service_id = nil
    alert.criticality = 5
    alert.generated = Time.now
    alert.closed = false
    alert.description = "Discovered that #{system.display_name} was unreachable as of #{alert.generated}."
    alert.short_description = "#{system.display_name} unreachable"
    alert.save
  end

  # Raises an alert from a hash of attributes; returns the saved Alert.
  #
  # Used by scheduler.rb to report failed Jobs. Keys: :system_id, :service_id,
  # :criticality, :description, :short_description, and optionally :events (an
  # Array of Event records to link). Omitted keys are left unset rather than
  # nilled, so callers may pass a partial hash.
  def self.genericAlert(params={})
    alert=Alert.new
    alert.system_id = params[:system_id] unless params[:system_id].nil?
    alert.service_id = params[:service_id] unless params[:service_id].nil?
    alert.criticality = params[:criticality]
    alert.generated = Time.now
    alert.closed = false
    alert.description = params[:description]
    alert.short_description = params[:short_description]
    alert.events = params[:events] unless params[:events].nil?
    alert.save
  end
end

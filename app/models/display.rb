# A per-log-format display rule: a regex that recognises an event line plus a
# declarative spec describing how to reformat it.
#
# Display.helper_for_event returns the first Display whose +key+ regex matches an
# event's raw text; Event#parsed then interprets that Display's +display_script+
# through DisplayRule. The spec is parsed, never evaluated, so editing a Display
# cannot execute Ruby.
class Display < ActiveRecord::Base
  has_many :display_fields

  validate :display_script_is_valid

  # Rejects a malformed display_script at save time, so a broken rule surfaces in
  # the form rather than while rendering the dashboard.
  def display_script_is_valid
    return if display_script.blank?
    DisplayRule.validate(display_script).each { |err| errors.add(:display_script, err) }
  end

  # Show the "Displays" tab only to users holding the Detective right.
  def self.hidden?(current_user = nil)
    return true if current_user.nil?
    return true unless current_user.has_right?("Detective")
    return false
  end

  # Returns the first Display whose +key+ matches +event_string+, else nil.
  #
  # Displays are tried in AR default order, so the first saved match wins;
  # ordering is significant when patterns overlap. A malformed or under-specified
  # pattern raises during Regexp.new/match; that is swallowed and evaluation
  # continues with the next Display, so a bad rule degrades to "no helper"
  # rather than breaking the page.
  def self.helper_for_event(event_string)
    Display.all.each do |filter|
      begin
        reg = Regexp.new(filter.key)
        return filter unless reg.match(event_string).nil?
      rescue
        Rails.logger.warn "Had to rescue: #{filter.key}"
        # Likely don't have enough fields.  Don't care to figure it out for now.
      end
    end
    return nil
  end

end

# A per-log-format display rule: a regex that recognises an event line plus the
# Ruby that renders it.
#
# Display.helper_for_event returns the first Display whose +key+ regex matches an
# event's raw text; Event#parsed then eval's that Display's +display_script+ and
# calls the +parse_event+ method it is expected to define. Editing a Display is
# therefore arbitrary code execution -- restrict the Detective right.
class Display < ActiveRecord::Base
  has_many :display_fields

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
        puts "Had to rescue: #{filter.key}"
        # Likely don't have enough fields.  Don't care to figure it out for now.
      end
    end
    return nil
  end

end

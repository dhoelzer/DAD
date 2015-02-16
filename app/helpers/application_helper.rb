module ApplicationHelper
  def is_active(controller)       
    params[:controller] == controller ? "active" : "inactive"     
  end
  
  def timestamp_helper(timestamp=Time.now)
    timezones = [
      "Eastern Time (US & Canada)",
      "Pacific Time (US & Canada)",
      "Asia/Seoul",
      "Europe/London",
      "Asia/Shanghai"]
    tooltip = ""
    timezones.each do |zone|
      tooltip = tooltip + "#{zone}: #{timestamp.in_time_zone(zone)}\n"
    end
    span = "<span class='timestamp' time=\"#{tooltip}\">#{timestamp}</span>"
    return span
  end
end

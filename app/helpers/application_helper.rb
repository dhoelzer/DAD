module ApplicationHelper
  def is_active(controller)       
    params[:controller] == controller ? "active" : "inactive"     
  end
  
  def tooltip_timestamps(timestamp=Time.now)
    timezones = [
      "Pacific Time (US & Canada)",
      "Asia/Seoul",
      "Europe/London",
      "Asia/Shanghai"]
    tooltip = ""
    timezones.each do |zone|
      tooltip = tooltip + "#{zone}: #{timestamp.in_time_zone(zone)}\n"
    end
    span = "<span class='timestamp'> time='#{tooltip}'>#{timestamp}</span>"
    return tooltip
  end
end

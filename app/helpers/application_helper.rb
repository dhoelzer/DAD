module ApplicationHelper
  def is_active(controller)       
    params[:controller] == controller ? "active" : "inactive"     
  end
  
  def tooltip_timestamp(timestamp=Time.now)
    timezones = [
      "Pacific Time (US & Canada)",
      "Asia/Seoul",
      "Europe/London",
      "Asia/Shanghai"]
    tooltip = ""
    timezones.each do |zone|
      tooltip = tooltip + "#{zone}: " + timestamp.in_time_zone(zone) + "<br>"
    end
    return tooltip
  end
end

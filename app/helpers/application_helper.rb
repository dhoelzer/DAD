module ApplicationHelper
  def is_active(controller)       
    params[:controller] == controller ? "active" : "inactive"     
  end
end

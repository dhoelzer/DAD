class Alert < ActiveRecord::Base
  has_and_belongs_to_many :events
  has_many :comments
  belongs_to :system
  belongs_to :service
  
  def self.hidden?
    return false
  end
  
  def criticality_name
    self.criticality == 0 ? "Debug" : self.criticality == 1 ? "Informational" : self.criticality == 2 ? "Warning" : self.criticality == 3 ? "Important" : self.criticality == "4" ? "Serious" : "Critical"
  end
  
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

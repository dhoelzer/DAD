class Alert < ActiveRecord::Base
  has_and_belongs_to_many :events
  has_many :comments
  belongs_to :system
  belongs_to :service
  
  def self.hidden?
    return false
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
  
  def self.genericAlert(*params)
    alert=Alert.new
    alert.system_id = params[:system_id]
    alert.service_id = params[:service_id]
    alert.criticality = params[:criticality]
    alert.generated = Time.now
    alert.closed = false
    alert.description = params[:description]
    alert.short_description = params[:short_description]
    alert.events = params[:events]
    alert.save
  end
end

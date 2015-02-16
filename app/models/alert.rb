class Alert < ActiveRecord::Base
  has_and_belongs_to_many :events
  has_many :comments
  belongs_to :system
  belongs_to :service
  
  def self.hidden?
    return false
  end
  
end

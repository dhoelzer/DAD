class Job < ActiveRecord::Base
  def self.hidden?
    return false
  end
end

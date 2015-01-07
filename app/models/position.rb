class Position < ActiveRecord::Base
  belongs_to :event
  belongs_to :word
end

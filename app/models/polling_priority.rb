# A polling interval band for Windows hosts.
#
# Three levels ship (Priority 1/2/3 at 5min/30min/6h ceilings), but the levels are
# rows rather than constants so an operator can add or retune them without a
# deploy. The poller reads only the two interval bounds and the enabled flag, so
# name and rank are presentation.
#
# The band is two-sided on purpose:
#
#   max_interval_secs is the priority guarantee. A Priority 1 host is polled at
#     least every 300s no matter how quiet it goes. This is the bound the
#     requirement names.
#   min_interval_secs is a separate guard: a host producing a torrent of events
#     must not be polled so aggressively that the polling itself becomes the
#     load, or that overlapping polls start against one host.
class PollingPriority < ActiveRecord::Base
  has_many :windows_targets

  # Hidden from the nav bar: priority levels are edited from the Windows Targets
  # screens, where their effect is visible next to the hosts using them.
  def self.hidden?(_current_user = nil)
    true
  end

  validates :name, presence: true, uniqueness: true
  validates :rank, presence: true, uniqueness: true,
                   numericality: { only_integer: true, greater_than: 0 }
  validates :min_interval_secs, :max_interval_secs,
            numericality: { only_integer: true, greater_than: 0 }
  validate :min_does_not_exceed_max

  # Levels an operator may assign, cheapest rank first.
  def self.ordered
    order(rank: :asc)
  end

  def to_s
    name
  end

  private

  # A band whose floor is above its ceiling cannot be satisfied: clamping into it
  # would return min, silently overriding the max the operator set, and the
  # "never polled less often than X" guarantee would be meaningless.
  def min_does_not_exceed_max
    return if min_interval_secs.nil? || max_interval_secs.nil?
    return if min_interval_secs <= max_interval_secs

    errors.add(:min_interval_secs,
               'must not exceed the maximum interval ' \
               "(#{min_interval_secs}s floor above #{max_interval_secs}s ceiling)")
  end
end

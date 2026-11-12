require 'ad_query'

# One previewed Active Directory import: the hosts a query returned, and whether
# they were actually added.
#
# The invariant this class exists to enforce:
#
#   apply() may only REMOVE from the stored candidate set. It can never add to it.
#
# That is not a UX nicety. A WindowsTarget row makes this server connect OUT to
# `address` carrying a domain credential. If apply() took the host list from the
# form, a crafted POST would create a target for any host an attacker named and
# hand it our WinRM credential -- SSRF with a domain login attached, arriving
# through a form whose only visible affordance is unchecking boxes. So the
# candidate set is written here at preview time, server-side, and the submitted
# selection is intersected with it. A name that was never offered cannot be
# imported, whatever is posted.
#
# The audit trail (who queried, what was returned, what was applied, when) comes
# along for free, which for a bulk operation that creates credential-bearing rows
# is worth having anyway.
class AdImportBatch < ActiveRecord::Base
  belongs_to :active_directory_connection
  belongs_to :user, optional: true

  # Not a nav tab. A batch has no index of its own -- it is reached from the
  # connection that produced it, and its history is listed there. Same reason
  # PollingPriority hides itself: the layout links every model in $_models to
  # Model.constantize, so a model without an index route would render a broken
  # tab.
  def self.hidden?(_current_user = nil)
    true
  end

  HOST_FILTERS = %w[all workstations servers].freeze

  validates :host_filter, inclusion: { in: HOST_FILTERS }
  validate :candidates_are_present

  # Candidate records are flat scalars only. JSON rather than YAML because
  # YAML.load on a stored blob is a deserialization footgun, and nothing here
  # needs a richer type than strings, booleans and integers.
  def candidates
    @candidates ||= begin
      raw = self[:candidates]
      raw.to_s.empty? ? [] : JSON.parse(raw)
    rescue JSON::ParserError
      []
    end
  end

  def candidates=(list)
    @candidates = list
    self[:candidates] = JSON.generate(list)
  end

  def applied?
    !applied_at.nil?
  end

  # Hosts the preview offered as new -- the ones the operator can actually add.
  def new_hosts
    candidates.reject { |c| c['already_present'] }
  end

  def already_present
    candidates.select { |c| c['already_present'] }
  end

  # Creates a WindowsTarget for each selected candidate that is still new.
  #
  # Returns {added:, skipped:, rejected:} rather than raising. A bulk import over
  # a few hundred hosts must not lose 399 because one had a name that failed
  # validation -- same principle as one unreadable event-log channel not costing
  # the host its other channels.
  #
  # `selected` is treated as a request, not an instruction. Anything in it that is
  # not in the stored candidate set lands in :rejected and creates nothing.
  def apply(selected, applied_by: nil)
    raise 'this batch has already been applied' if applied?

    wanted = Array(selected).map { |a| a.to_s.strip }.reject(&:empty?).uniq
    offered = candidates.reject { |c| c['already_present'] }
    offered_addresses = offered.map { |c| c['address'] }

    # The security boundary. Intersect, never union.
    accepted = offered_addresses & wanted
    rejected   = wanted - offered_addresses
    deselected = offered_addresses - wanted

    defaults = active_directory_connection.import_defaults
    added = []
    skipped = []

    accepted.each do |address|
      candidate = offered.find { |c| c['address'] == address }

      # Re-checked at apply time, not just at preview: a target may have been
      # created by hand between the two, and two rows for one host would
      # double-poll it and interleave two independent offset states. Matched on
      # either alias form, so an existing "web01" blocks importing
      # "web01.corp.example.com" as a second target for the same machine.
      if AdQuery.already_present([address]).any?
        skipped << address
        next
      end

      target = WindowsTarget.new(
        address: address,
        name: candidate['name'],
        polling_priority_id: defaults[:polling_priority_id],
        event_logs: defaults[:event_logs],
        username: defaults[:username],
        enabled: true
      )
      # Assigned rather than passed to new: an empty string through the
      # constructor would store an empty credential, and the model's
      # blank-means-keep-it guard lives in the controller, not here.
      target.password = defaults[:password] if defaults[:password].present?

      if target.save
        added << address
      else
        skipped << "#{address} (#{target.errors.full_messages.join(', ')})"
      end
    end

    self.applied_at = Time.now
    self.added_count = added.size
    save!

    { added: added, skipped: skipped, deselected: deselected, rejected: rejected,
      applied_by: applied_by }
  end

  private

  def candidates_are_present
    return if self[:candidates].present? && !candidates.empty?
    errors.add(:candidates, 'must list at least one candidate host')
  end
end

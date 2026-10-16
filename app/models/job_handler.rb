# The closed set of things a scheduled Job is allowed to do.
#
# Replaces the previous design, in which scheduler.rb ran eval(job.script) and a
# Job row was therefore arbitrary Ruby executing as the scheduler user (root
# under provision.sh). Creating a Job is now choosing a name from HANDLERS plus a
# scalar argument; no user-authored code is stored or executed anywhere.
#
# Adding capability means adding an entry here and deploying -- it is deliberately
# not something an operator can do from the web UI.
class JobHandler
  class UnknownHandler < StandardError; end

  # Registered handlers, keyed by the name stored in Job#script.
  #
  # Each value takes a single optional scalar argument and returns a String
  # summary for the log. Keep handlers idempotent: the scheduler re-runs a
  # failing Job on the next cycle forever.
  HANDLERS = {
    'prune_words' => ->(_arg) { EventIngestor.prune_words; 'pruned word cache' },
    'reset_caches' => ->(_arg) { EventIngestor.resetCaches; 'reset class-level caches' },
    'reset_stats' => ->(_arg) { EventIngestor.resetStats; 'reset throughput clock' },
    'disk_utilization' => lambda do |_arg|
      used = Event.diskUtilization
      # nil means df could not measure the archive partition. Reporting "0%"
      # would claim an empty disk, which is the opposite of the truth and the
      # reason the old helper was unsafe to act on.
      used.nil? ? 'disk utilization unknown: cannot measure the archive partition' \
                : "disk utilization #{used}% of #{EventPartitionBackup.storage_dir}"
    end,
    'maintain_event_partitions' => ->(_arg) { EventPartitioning.maintain },
    'tune_dashboard_feed' => ->(_arg) { Event.tune_dashboard_feed_size },
  }.freeze

  # Names an operator may select in the Jobs form.
  def self.names
    HANDLERS.keys.sort
  end

  def self.known?(name)
    HANDLERS.key?(name.to_s)
  end

  # Runs the named handler, returning a String summary.
  #
  # Raises UnknownHandler rather than falling back to eval: an unrecognised name
  # is a data error (or a tampered row), not something to interpret.
  def self.perform(name, arg = nil)
    handler = HANDLERS[name.to_s]
    raise UnknownHandler, "no such job handler: #{name.inspect}" if handler.nil?
    handler.call(arg)
  end
end

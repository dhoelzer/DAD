# A daemon/process name parsed out of a syslog line (e.g. "sshd", "postfix").
#
# Populated during ingestion: Event.storeEvent takes the token at the service
# offset and resolves it through Service.find_or_add. Events keep a service_id
# foreign key, so grouping and filtering by service is a plain join.
class Service < ActiveRecord::Base
  has_many :events
  has_many :servers, :through => :events

  # Process-local memo of name -> Service row, so a busy ingest does not hit the
  # DB once per line. Never expired: safe for the long-running importer because
  # service names are few and stable. Cleared only by restarting the process.
  @@cached_stuff = Hash.new
  @added = 0

  # Show the "Services" tab only to users holding the Viewer right.
  def self.hidden?(current_user = nil)
    return true if current_user.nil?
    return true unless current_user.has_right?("Viewer")
    return false
  end

  # Returns the Service named +new_item+, creating it on first sight.
  #
  # Called from the ingestion hot path (Event.storeEvent). Results are memoised
  # in @@cached_stuff, so repeat lookups cost nothing. Not thread-safe: two
  # concurrent callers could both miss the cache and race to create a row.
  def self.find_or_add(new_item)
    return @@cached_stuff[new_item] if @@cached_stuff.has_key?(new_item)
    item=Service.find_by name: new_item
    if item.nil? then
      item = Service.create(:name => new_item)
      @added += 1
    end
    @@cached_stuff[new_item] = item
    return item
  end

  # Number of Services memoised in this process (diagnostics/monitoring).
  def self.number_of_cached_items
    return @@cached_stuff.size
  end

  # How many Services this process has created (diagnostics/monitoring).
  def self.added
    return @added
  end
end

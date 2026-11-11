require 'ad_query'

# The two-step Active Directory import: query, then apply what survived review.
#
# Flow:
#   new     -> pick a connection and workstations / servers / both
#   create  -> query AD, persist the result as an AdImportBatch, redirect to it
#   show    -> the candidate list, each new host pre-selected, with the option to
#              uncheck any of them
#   apply   -> create a WindowsTarget for each still-selected candidate
#
# The batch is persisted between the query and the apply rather than carried
# through the form, and that is a security property, not a convenience. A
# WindowsTarget makes this server connect OUT to `address` carrying a domain
# credential, so if the apply step took host names from the submitted form, a
# crafted POST would add any host an attacker named and hand it our credential.
# AdImportBatch#apply intersects the selection with the stored candidate set, so
# the browser can only ever subtract. See that class for the full reasoning.
#
# Admin only throughout.
class AdImportBatchesController < ApplicationController
  before_action :set_batch, only: [:show, :apply]

  # The form that starts a query. Every enabled connection is offered, including
  # one with no polling credential -- importing the inventory first and setting the
  # credential afterwards is a legitimate order of work. What is not acceptable is
  # doing that silently, so those connections are named in a warning on the same
  # page rather than hidden from the dropdown.
  def new
    @connections = ActiveDirectoryConnection.enabled.order(:name)
    @missing_credential = @connections.reject(&:polling_credential_present?)
  end

  # Runs the query and stores the result. Does not import anything.
  def create
    connection = ActiveDirectoryConnection.find(params[:active_directory_connection_id])
    host_filter = params[:host_filter].to_s
    host_filter = 'all' unless AdImportBatch::HOST_FILTERS.include?(host_filter)

    batch = AdImportBatch.new(active_directory_connection: connection,
                              user: @current_user,
                              host_filter: host_filter)

    entries, present, unnamed = AdQuery.run(connection, host_filter: host_filter)

    if entries.empty?
      # Recorded as a status, not as a batch: an empty batch has no candidates
      # to review, and storing one would fail validation with a message about
      # candidates that tells the operator nothing about the directory.
      connection.update!(last_query_at: Time.now,
                         last_status: 'query returned no computer objects'[0, 255])
      redirect_to new_ad_import_batch_path,
                  alert: "The query returned no computer objects. Check the search " \
                         'base, the filter, and that the bind account can read ' \
                         'computer objects.'
      return
    end

    batch.candidates = build_candidates(entries, present)

    if batch.save
      connection.update!(last_query_at: Time.now,
                         last_status: "queried #{entries.size} computer object(s), " \
                                      "#{batch.new_hosts.size} new"[0, 255])
      flash[:notice] = skipped_note(unnamed) if unnamed.positive?
      redirect_to ad_import_batch_path(batch)
    else
      redirect_to new_ad_import_batch_path,
                  alert: "Could not record the query: #{batch.errors.full_messages.join(', ')}"
    end
  rescue ArgumentError => e
    redirect_to new_ad_import_batch_path, alert: e.message
  rescue ActiveRecord::RecordNotFound
    redirect_to new_ad_import_batch_path, alert: 'No such Active Directory connection.'
  rescue StandardError => e
    # A bad bind, an unreachable domain controller, or a refused search are all
    # ordinary conditions. They must read as a message on the page, not as a 500
    # -- and must not be swallowed into "no new hosts", which is the failure
    # mode that looks like success.
    connection&.update!(last_status: "#{e.class}: #{e.message}"[0, 255])
    redirect_to new_ad_import_batch_path,
                alert: "Querying #{connection&.display_name} failed: #{e.class}: #{e.message}"
  end

  # The review page. Nothing has been imported at this point.
  def show
  end

  # Creates the selected hosts.
  def apply
    return redirect_to(ad_import_batch_path(@batch)) if @batch.applied?

    selected = Array(params[:selected_addresses]).map(&:to_s)
    result = @batch.apply(selected, applied_by: @current_user.username)

    flash[:notice] = import_summary(result)

    # flash.now would not survive the redirect below, and this is the one
    # message that must be seen: it says the submission asked for hosts the
    # query never returned.
    unless result[:rejected].empty?
      flash[:alert] = "Ignored #{result[:rejected].size} address(es) that this " \
                      'query never returned. Only hosts offered by the preview ' \
                      'can be added.'
    end

    redirect_to windows_targets_path
  end

  private

  def set_batch
    @batch = AdImportBatch.find(params[:id])
  end

  # Computer objects with no dNSHostName cannot be polled, and an operator who
  # sees a count lower than the domain has will assume the filter is to blame.
  def skipped_note(unnamed)
    return nil if unnamed.zero?
    "#{unnamed} computer object(s) were skipped for having no DNS hostname; " \
    'they cannot be polled over WinRM.'
  end

  # Candidate rows, in the shape AdImportBatch stores and the preview renders.
  #
  # Sorted so domain controllers and unknown-OS hosts sit at the top: those are
  # the two categories an operator most needs to look at before clicking import,
  # and on a few hundred rows they would otherwise be scattered alphabetically.
  def build_candidates(entries, present)
    present_set = present.map(&:downcase)

    entries.map do |e|
      {
        'address' => e.address,
        'name' => e.name,
        'operating_system' => e.operating_system,
        'host_class' => e.host_class.to_s,
        'domain_controller' => e.domain_controller,
        'already_present' => present_set.include?(e.address) ||
                             present_set.include?(e.address.split('.').first)
      }
    end.sort_by do |c|
      [c['already_present'] ? 1 : 0,
       c['domain_controller'] ? 0 : 1,
       c['host_class'] == 'unknown' ? 0 : 1,
       c['address']]
    end
  end

  def import_summary(result)
    parts = ["Imported #{result[:added].size} Windows target(s)."]
    parts << "#{result[:deselected].size} left out." unless result[:deselected].empty?
    parts << "#{result[:skipped].size} skipped: #{result[:skipped].join(', ')}" unless result[:skipped].empty?
    parts.join(' ')
  end
end

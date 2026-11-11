# Management screens for the list of Windows hosts DAD polls over WinRM.
#
# Reading is a Viewer action; writing is Admin (see ApplicationController's
# rights maps), because a WindowsTarget row holds a domain credential and names
# a host this server will connect out to.
#
# There is no destroy action, matching SystemsController: a host taken out of
# rotation is disabled, which keeps its measured rate and credentials and leaves
# a record of what was being collected. Deleting the row would also orphan the
# Events ingested under its address.
class WindowsTargetsController < ApplicationController
  before_action :set_windows_target, only: [:show, :edit, :update, :poll_now]

  def index
    @windows_targets = paginate(WindowsTarget.all, order: :address)
    respond_to do |format|
      format.html
      # Bare, not `render json:`: that path serializes the whole record through
      # as_json, which would publish the stored ciphertext. This renders
      # index.json.jbuilder, which names its fields.
      format.json
    end
  end

  def show
  end

  def new
    @windows_target = WindowsTarget.new(polling_priority: PollingPriority.ordered.first)
  end

  def edit
  end

  def create
    @windows_target = WindowsTarget.new(windows_target_params)
    apply_password

    respond_to do |format|
      if @windows_target.save
        format.html { redirect_to @windows_target, notice: 'Windows target was successfully created.' }
        format.json { render :show, status: :created, location: @windows_target }
      else
        format.html { render action: 'new' }
        format.json { render json: @windows_target.errors, status: :unprocessable_entity }
      end
    end
  end

  def update
    @windows_target.assign_attributes(windows_target_params)
    apply_password

    respond_to do |format|
      if @windows_target.save
        format.html { redirect_to @windows_target, notice: 'Windows target was successfully updated.' }
        format.json { head :no_content }
      else
        format.html { render action: 'edit' }
        format.json { render json: @windows_target.errors, status: :unprocessable_entity }
      end
    end
  end

  # Polls one target immediately, without waiting for its next_poll_at.
  #
  # This is the operator's check that credentials and channel selection actually
  # work, which is otherwise only visible by waiting minutes for a scheduled
  # poll and then reading a log. It runs inline rather than queueing a Job so
  # the result comes back in the response.
  def poll_now
    result = WindowsPoll.poll(@windows_target)
    @windows_target.record_poll!(event_count: result.event_count, status: result.status)

    if result.status == 'ok'
      redirect_to @windows_target,
                  notice: "Polled #{@windows_target.address}: #{result.event_count} event(s) queued."
    else
      redirect_to @windows_target, alert: "Polling #{@windows_target.address} reported: #{result.detail}"
    end
  rescue StandardError => e
    # A host that is down or unreachable is expected; it must surface as a
    # message on the page, not as a 500.
    redirect_to @windows_target, alert: "Polling #{@windows_target.address} failed: #{e.class}: #{e.message}"
  end

  private

  def set_windows_target
    @windows_target = WindowsTarget.find(params[:id])
  end

  # password is deliberately absent: it is handled by #apply_password, and
  # permitting it here would let a blank form submission overwrite a stored
  # credential with an empty string.
  def windows_target_params
    params.require(:windows_target)
          .permit(:address, :name, :polling_priority_id, :event_logs, :enabled, :username)
  end

  # Sets the credential only when the form actually supplied one.
  #
  # The edit form never renders the stored password -- it is encrypted at rest
  # and has no reason to reach a browser, a proxy log, or page history. That
  # means an untouched password field arrives blank, and treating blank as "set
  # it to blank" would wipe the credential on every unrelated edit. Same shape
  # as the Users screens' handling of password hashes.
  def apply_password
    supplied = params.dig(:windows_target, :password)
    return if supplied.nil? || (supplied.respond_to?(:empty?) && supplied.empty?)
    @windows_target.password = supplied
  end
end

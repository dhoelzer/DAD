# The alert queue: open findings raised against hosts, acknowledged by operators.
#
# Alerts arrive from the dashboard reachability check (Alert.hostUnreachable), from
# the scheduler when a Job fails (Alert.genericAlert), and by hand through the CRUD
# actions below.
class AlertsController < ApplicationController
  before_action :set_alert, only: [:show, :edit, :update, :destroy, :acknowledge]

  # Requires Viewer or Commentator; replaces the ApplicationController default.
  # Commentator is accepted because acknowledging an alert is an operator action.
  def authorized?  
    if @current_user.nil? then
      flash[:notice] = "Not authorized"
      redirect_to logon_users_path
      return false
    end
    return true if(@current_user.has_right?("Viewer") || @current_user.has_right?("Commentator"))
    flash[:notice] = "You lack the appropriate rights"
    redirect_to logon_users_path
    return false
  end

  # GET /alerts (and .json) -- the open-alert queue, most critical first and oldest
  # first within a level. Closed alerts are not listed.
  def index
    @alerts = Alert.where(:closed => false).order("criticality DESC").order(:generated)
  end

  # GET /alerts/1 (and .json) -- one alert with its comments and linked events.
  # @remote drives whether the view renders standalone or embedded in the dashboard.
  def show
      @remote = false
  end

  # GET /alerts/1/edit
  def edit
  end

  # PATCH/PUT /alerts/1.json
  def update
    respond_to do |format|
      if @alert.update(alert_params)
        format.html { redirect_to @alert, notice: 'Alert was successfully updated.' }
        format.json { head :no_content }
      else
        format.html { render action: 'edit' }
        format.json { render json: @alert.errors, status: :unprocessable_entity }
      end
    end
  end
  
  # POST /alerts/ackall (JS only) -- acknowledges every open alert at once by setting
  # closed = true, then re-renders the queue. Unscoped and unconfirmed: one click
  # closes every alert.
  def ackall
    alerts=Alert.where(:closed => false)
    alerts.each do |alert|
      alert.closed = true
      alert.save
    end
    @alerts = Alert.where(:closed => false).order("criticality DESC").order(:generated)    
    respond_to do |format|
      format.js {render layout: false }
    end
  end
  
  # POST /alerts/:id/acknowledge -- acknowledges one alert (closed = true) and
  # re-renders the queue, as JS or a redirect depending on the request format.
  def acknowledge
    @alert.closed = true
    @alert.save
    @alerts = Alert.where(:closed => false).order("criticality DESC").order(:generated)    
    respond_to do |format|
      format.js {render layout: false }
      format.html {redirect_to alerts_url; return}
    end
  end
  
  # DELETE /alerts/1.json
  def destroy
    @alert.destroy
    respond_to do |format|
      format.html { redirect_to alerts_url }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    # Loads @alert from params[:id]; raises 404 when there is no such record. Internal:
    # runs as a before_action for show/edit/update/destroy/acknowledge.
    def set_alert
      @alert = Alert.find(params[:id])
    end

    # Never trust parameters from the scary internet, only allow the white list through.
    # Attribute whitelist for alert writes. Note :closed is writable here, so the edit
    # form can open or close an alert independently of #acknowledge.
    def alert_params
      params.require(:alert).permit(:system_id, :service_id, :criticality, :generated, :event_id, :closed, :description, :short_description)
    end
end

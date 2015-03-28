class AlertsController < ApplicationController
  before_action :set_alert, only: [:show, :edit, :update, :destroy, :acknowledge]

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

  # GET /alerts
  # GET /alerts.json
  def index
    @alerts = Alert.where(:closed => false).order("criticality DESC").order(:generated)
  end

  # GET /alerts/1
  # GET /alerts/1.json
  def show
      @remote = false
  end

  # GET /alerts/1/edit
  def edit
  end

  # PATCH/PUT /alerts/1
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
  
  def ackall
    alerts=Alert.where(:closed => false)
    alerts.each do |alert|
      alert.closed = true
      alert.save
    end
    @alerts = Alert.where(:closed => false).order(:criticality).order(:generated)    
    respond_to do |format|
      format.js {render layout: false }
    end
  end
  
  def acknowledge
    @alert.closed = true
    @alert.save
    @alerts = Alert.where(:closed => false).order(:criticality).order(:generated)    
    respond_to do |format|
      format.js {render layout: false }
      format.html {redirect_to alerts_url; return}
    end
  end
  
  # DELETE /alerts/1
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
    def set_alert
      @alert = Alert.find(params[:id])
    end

    # Never trust parameters from the scary internet, only allow the white list through.
    def alert_params
      params.require(:alert).permit(:system_id, :service_id, :criticality, :generated, :event_id, :closed, :description, :short_description)
    end
end

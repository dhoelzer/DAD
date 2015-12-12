class SystemsController < ApplicationController
  before_action :set_system, only: [:show, :edit, :update]

  def authorized?  
    if @current_user.nil? then
      flash[:notice] = "Not authorized"
      redirect_to logon_users_path
      return false
    end
    return true if(@current_user.has_right?("Viewer"))
    flash[:notice] = "You lack the appropriate rights"
    redirect_to logon_users_path
    return false
  end

  # GET /systems
  # GET /systems.json
  def index
    #@systems = System.order(name: :asc).all
    @reportingInLast24 = System.reportingInLastDays(1)
    @systems = @reportingInLast24
    respond_to do |format|
      format.html
      format.js {render layout: false}
    end
  end

  # GET /systems/1
  # GET /systems/1.json
  def show
    @events = Event.where(:system => @system).limit(25).order(generated: :desc).reverse
  end

  # GET /systems/new
  def new
    @system = System.new
  end

  # GET /systems/1/edit
  def edit
  end

  # POST /systems
  # POST /systems.json
  def create
    @system = System.new(system_params)

    respond_to do |format|
      if @system.save
        format.html { redirect_to @system, notice: 'System was successfully created.' }
        format.json { render action: 'show', status: :created, location: @system }
      else
        format.html { render action: 'new' }
        format.json { render json: @system.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /systems/1
  # PATCH/PUT /systems/1.json
  def update
    respond_to do |format|
      if @system.update(system_params)
        format.html { redirect_to @system, notice: 'System was successfully updated.' }
        format.json { head :no_content }
      else
        format.html { render action: 'edit' }
        format.json { render json: @system.errors, status: :unprocessable_entity }
      end
    end
  end


  private
    # Use callbacks to share common setup or constraints between actions.
    def set_system
      @system = System.find(params[:id])
    end

    # Never trust parameters from the scary internet, only allow the white list through.
    def system_params
      params.require(:system).permit(:address, :description, :administrator, :contact_email, :monitor, :name)
    end
end

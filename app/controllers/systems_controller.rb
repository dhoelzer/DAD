class SystemsController < ApplicationController
  before_action :set_system, only: [:show, :edit, :update, :destroy]

  # GET /systems
  # GET /systems.json
  def index
    @systems = System.all
  end

  # GET /systems/1
  # GET /systems/1.json
  def show
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

  # DELETE /systems/1
  # DELETE /systems/1.json
  def destroy
    @system.destroy
    respond_to do |format|
      format.html { redirect_to systems_url }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_system
      @system = System.find(params[:id])
    end

    # Never trust parameters from the scary internet, only allow the white list through.
    def system_params
      params.require(:system).permit(:address, :name, :description, :administrator, :contact_email)
    end
end

class DisplayFieldsController < ApplicationController
  before_action :set_display_field, only: [:show, :edit, :update, :destroy]

  def authorized?  
    if @current_user.nil? then
      flash[:notice] = "Not authorized"
      redirect_to logon_users_path
      return false
    end
    return true if(@current_user.has_right?("Detective"))
    flash[:notice] = "You lack the appropriate rights"
    redirect_to logon_users_path
    return false
  end

  # GET /display_fields
  # GET /display_fields.json
  def index
    @display_fields = DisplayField.all
  end

  # GET /display_fields/1
  # GET /display_fields/1.json
  def show
  end

  # GET /display_fields/new
  def new
    @display_field = DisplayField.new
  end

  # GET /display_fields/1/edit
  def edit
  end

  # POST /display_fields
  # POST /display_fields.json
  def create
    @display_field = DisplayField.new(display_field_params)

    respond_to do |format|
      if @display_field.save
        format.html { redirect_to @display_field, notice: 'Display field was successfully created.' }
        format.json { render action: 'show', status: :created, location: @display_field }
      else
        format.html { render action: 'new' }
        format.json { render json: @display_field.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /display_fields/1
  # PATCH/PUT /display_fields/1.json
  def update
    respond_to do |format|
      if @display_field.update(display_field_params)
        format.html { redirect_to @display_field, notice: 'Display field was successfully updated.' }
        format.json { head :no_content }
      else
        format.html { render action: 'edit' }
        format.json { render json: @display_field.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /display_fields/1
  # DELETE /display_fields/1.json
  def destroy
    @display_field.destroy
    respond_to do |format|
      format.html { redirect_to display_fields_url }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_display_field
      @display_field = DisplayField.find(params[:id])
    end

    # Never trust parameters from the scary internet, only allow the white list through.
    def display_field_params
      params.require(:display_field).permit(:display_id, :field_position, :title, :order)
    end
end

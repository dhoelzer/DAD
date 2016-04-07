class HunksController < ApplicationController
  before_action :set_hunk, only: [:show, :edit, :update, :destroy]

  def authorized?  
    if @current_user.nil? then
      flash[:notice] = "Not authorized"
      redirect_to logon_users_path
      return false
    end
    return true if(@current_user.has_right?("Admin"))
    flash[:notice] = "You lack the appropriate rights"
    redirect_to logon_users_path
    return false
  end
  # GET /hunks
  # GET /hunks.json
  def index
    @hunks = Hunk.all
  end

  # GET /hunks/1
  # GET /hunks/1.json
  def show
  end

  # GET /hunks/new
  def new
    @hunk = Hunk.new
  end

  # GET /hunks/1/edit
  def edit
  end

  # POST /hunks
  # POST /hunks.json
  def create
    @hunk = Hunk.new(hunk_params)

    respond_to do |format|
      if @hunk.save
        format.html { redirect_to @hunk, notice: 'Hunk was successfully created.' }
        format.json { render action: 'show', status: :created, location: @hunk }
      else
        format.html { render action: 'new' }
        format.json { render json: @hunk.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /hunks/1
  # PATCH/PUT /hunks/1.json
  def update
    respond_to do |format|
      if @hunk.update(hunk_params)
        format.html { redirect_to @hunk, notice: 'Hunk was successfully updated.' }
        format.json { head :no_content }
      else
        format.html { render action: 'edit' }
        format.json { render json: @hunk.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /hunks/1
  # DELETE /hunks/1.json
  def destroy
    @hunk.destroy
    respond_to do |format|
      format.html { redirect_to hunks_url }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_hunk
      @hunk = Hunk.find(params[:id])
    end

    # Never trust parameters from the scary internet, only allow the white list through.
    def hunk_params
      params.require(:hunk).permit(:text)
    end
end

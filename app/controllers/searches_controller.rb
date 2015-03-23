class SearchesController < ApplicationController
  before_action :set_search, only: [:show, :edit, :update, :destroy]

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

  # GET /searches
  # GET /searches.json
  def index
    @searches = Search.all
  end

  # GET /searches/1
  # GET /searches/1.json
  def show
    unless @current_user.has_right?("Viewer") 
      flash[:notice] = "You lack the appropriate rights"
      redirect_to events_path    
      return
    end
  end

  # GET /searches/new
  def new
    unless @current_user.has_right?("Detective") 
      flash[:notice] = "You lack the appropriate rights"
      redirect_to events_path    
      return
    end
    @search = Search.new
  end

  # GET /searches/1/edit
  def edit
    unless @current_user.has_right?("Detective") 
      flash[:notice] = "You lack the appropriate rights"
      redirect_to events_path    
      return
    end
  end

  # POST /searches
  # POST /searches.json
  def create
    unless @current_user.has_right?("Detective") 
      flash[:notice] = "You lack the appropriate rights"
      redirect_to events_path    
      return
    end
    @search = Search.new(search_params)

    respond_to do |format|
      if @search.save
        format.html { redirect_to @search, notice: 'Search was successfully created.' }
        format.json { render action: 'show', status: :created, location: @search }
      else
        format.html { render action: 'new' }
        format.json { render json: @search.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /searches/1
  # PATCH/PUT /searches/1.json
  def update
    unless @current_user.has_right?("Detective") 
      flash[:notice] = "You lack the appropriate rights"
      redirect_to events_path    
      return
    end
    respond_to do |format|
      if @search.update(search_params)
        format.html { redirect_to @search, notice: 'Search was successfully updated.' }
        format.json { head :no_content }
      else
        format.html { render action: 'edit' }
        format.json { render json: @search.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /searches/1
  # DELETE /searches/1.json
  def destroy
    unless @current_user.has_right?("Detective") 
      flash[:notice] = "You lack the appropriate rights"
      redirect_to events_path    
      return
    end
    @search.destroy
    respond_to do |format|
      format.html { redirect_to searches_url }
      format.json { head :no_content }
    end
  end

  private
  # Use callbacks to share common setup or constraints between actions.
  def set_search
    @search = Search.find(params[:id])
  end

  # Never trust parameters from the scary internet, only allow the white list through.
  def search_params
    params.require(:search).permit(:string, :user_id, :description, :short_description)
  end
end

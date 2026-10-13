# Management screens for Search records; requires the Detective right.
#
# A saved search is a bookmark: the stored string and time window re-populate the
# events search form. The query itself is still executed by Event.search.
class SearchesController < ApplicationController
  before_action :set_search, only: [:show, :edit, :update, :destroy]

  # Replaces the inherited ApplicationController#authorized? for every
  # action in this controller. Requires the Detective right; otherwise flashes a
  # notice and redirects to the logon page. Returning false stops the action.
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

  # Lists all searches records. No pagination or filtering.
  def index
    @searches = Search.all
  end

  # One search, addressed by id. @search is loaded by the
  # before_action; the .json form returns the record as JSON.
  def show
    unless @current_user.has_right?("Viewer") 
      flash[:notice] = "You lack the appropriate rights"
      redirect_to events_path    
      return
    end
  end

  # Blank form for creating a search.
  def new
    unless @current_user.has_right?("Detective") 
      flash[:notice] = "You lack the appropriate rights"
      redirect_to events_path    
      return
    end
    @search = Search.new
  end

  # Form for changing an existing search.
  def edit
    unless @current_user.has_right?("Detective") 
      flash[:notice] = "You lack the appropriate rights"
      redirect_to events_path    
      return
    end
  end

  # Inserts a search built from the whitelist in #search_params.
  # Re-renders the form with validation errors when the save fails.
  def create
    unless @current_user.has_right?("Detective") 
      flash[:notice] = "You lack the appropriate rights"
      redirect_to events_path    
      return
    end
    @search = Search.new(search_params)
    @search.user_id = @current_user.id
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

  # Applies the whitelisted attributes to the @search loaded by the
  # before_action; re-renders the form on failure.
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

  # Deletes the @search.
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
  # Loads @search from params[:id]; raises 404 when no such
  # record exists. Internal: runs as a before_action.
  def set_search
    @search = Search.find(params[:id])
  end

  # Attribute whitelist for search writes; any param not
  # listed here is dropped before it reaches the model.
  def search_params
    params.require(:search).permit(:string, :user_id, :description, :short_description)
  end
end

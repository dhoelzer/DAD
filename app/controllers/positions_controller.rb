class PositionsController < ApplicationController
  before_action :set_position, only: [:show]

  def authorized?  
    if @current_user.nil? then
      flash[:notice] = "Not authorized"
      redirect_to logon_users_path
      return false
    end
    return true if(@current_user.has_right?(Right.find_by_name("Admin")))
    flash[:notice] = "You lack the appropriate rights"
    redirect_to logon_users_path
    return false
  end

  # GET /positions
  # GET /positions.json
  def index
    @positions = Position.all.offset(0).limit(20)
  end

  # GET /positions/1
  # GET /positions/1.json
  def show
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_position
      @position = Position.find(params[:id])
    end
end

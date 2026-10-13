# Management screens for Comment records; requires the Commentator right.
#
# Comments are always attributed to @current_user, never to a user id in params.
# Standard scaffold actions; all writes go through the comment_params whitelist.
class CommentsController < ApplicationController
  before_action :set_comment, only: [:show, :edit, :update, :destroy]

  # Replaces the inherited ApplicationController#authorized? for every
  # action in this controller. Requires the Commentator right; otherwise flashes a
  # notice and redirects to the logon page. Returning false stops the action.
  def authorized?  
    if @current_user.nil? then
      flash[:notice] = "Not authorized"
      redirect_to logon_users_path
      return false
    end
    return true if(@current_user.has_right?("Commentator"))
    flash[:notice] = "You lack the appropriate rights"
    redirect_to logon_users_path
    return false
  end

  # Lists all comments records. No pagination or filtering.
  def index
    @comments = Comment.all
  end

  # One comment, addressed by id. @comment is loaded by the
  # before_action; the .json form returns the record as JSON.
  def show
  end

  # Blank form for creating a comment.
  def new
    @comment = Comment.new
    @comment.alert_id = params[:alert_id] if !params[:alert_id].nil? && Alert.find(params[:alert_id])
  end

  # Form for changing an existing comment.
  def edit
  end

  # Inserts a comment built from the whitelist in #comment_params.
  # Re-renders the form with validation errors when the save fails.
  def create
    @comment = Comment.new(comment_params)
    @comment.user_id = @current_user.id
    @comment.alert_id = params[:alert_id] if !params[:alert_id].nil? && Alert.find(params[:alert_id])    
    respond_to do |format|
      if @comment.save
        format.html { redirect_to @comment, notice: 'Comment was successfully created.' }
        format.json { render action: 'show', status: :created, location: @comment }
      else
        format.html { render action: 'new' }
        format.json { render json: @comment.errors, status: :unprocessable_entity }
      end
    end
  end

  # Applies the whitelisted attributes to the @comment loaded by the
  # before_action; re-renders the form on failure.
  def update
    respond_to do |format|
      if @comment.update(comment_params)
        format.html { redirect_to @comment, notice: 'Comment was successfully updated.' }
        format.json { head :no_content }
      else
        format.html { render action: 'edit' }
        format.json { render json: @comment.errors, status: :unprocessable_entity }
      end
    end
  end

  # Deletes the @comment.
  def destroy
    @comment.destroy
    respond_to do |format|
      format.html { redirect_to comments_url }
      format.json { head :no_content }
    end
  end

  private
    # Loads @comment from params[:id]; raises 404 when no such
    # record exists. Internal: runs as a before_action.
    def set_comment
      @comment = Comment.find(params[:id])
    end

    # Attribute whitelist for comment writes; any param not
    # listed here is dropped before it reaches the model.
    def comment_params
      params.require(:comment).permit(:message, :user_id, :alert_id)
    end
end

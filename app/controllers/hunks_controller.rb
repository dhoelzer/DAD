# Management screens for Hunk records; requires the Admin right.
#
# Hunks are a legacy token table that nothing else in the app reads (see Hunk),
# so these screens are effectively dead weight kept for direct data inspection.
class HunksController < ApplicationController
  before_action :set_hunk, only: [:show, :edit, :update, :destroy]

  # Lists all hunks records. No pagination or filtering.
  def index
    @hunks = Hunk.all
  end

  # One hunk, addressed by id. @hunk is loaded by the
  # before_action; the .json form returns the record as JSON.
  def show
  end

  # Blank form for creating a hunk.
  def new
    @hunk = Hunk.new
  end

  # Form for changing an existing hunk.
  def edit
  end

  # Inserts a hunk built from the whitelist in #hunk_params.
  # Re-renders the form with validation errors when the save fails.
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

  # Applies the whitelisted attributes to the @hunk loaded by the
  # before_action; re-renders the form on failure.
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

  # Deletes the @hunk.
  def destroy
    @hunk.destroy
    respond_to do |format|
      format.html { redirect_to hunks_url }
      format.json { head :no_content }
    end
  end

  private
    # Loads @hunk from params[:id]; raises 404 when no such
    # record exists. Internal: runs as a before_action.
    def set_hunk
      @hunk = Hunk.find(params[:id])
    end

    # Attribute whitelist for hunk writes; any param not
    # listed here is dropped before it reaches the model.
    def hunk_params
      params.require(:hunk).permit(:text)
    end
end

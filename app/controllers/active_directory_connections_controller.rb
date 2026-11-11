# CRUD for the Active Directory domains DAD can query for hosts.
#
# Admin only, including reads. That is stricter than windows_targets, where
# reading the list is a Viewer action, and the difference is deliberate: the
# sensitive act here is not saving a row, it is the enumeration. A query returns
# the entire machine inventory of a domain -- hostname, OS version, creation
# date -- which is reconnaissance-grade information about the internal network
# regardless of what gets imported afterwards.
class ActiveDirectoryConnectionsController < ApplicationController
  before_action :set_connection, only: [:show, :edit, :update]

  def index
    @connections = paginate(ActiveDirectoryConnection.all, order: :name)
    respond_to do |format|
      format.html
      # Bare `format.json`, not `render json:` -- the latter serializes the whole
      # record through as_json and would publish the stored ciphertext.
      format.json
    end
  end

  def show
  end

  def new
    @connection = ActiveDirectoryConnection.new(
      polling_priority: PollingPriority.ordered.first, port: 636)
  end

  def edit
  end

  def create
    @connection = ActiveDirectoryConnection.new(connection_params)
    apply_credentials

    respond_to do |format|
      if @connection.save
        format.html { redirect_to @connection, notice: 'Active Directory connection was successfully created.' }
        format.json { render :show, status: :created, location: @connection }
      else
        format.html { render action: 'new' }
        format.json { render json: @connection.errors, status: :unprocessable_entity }
      end
    end
  end

  def update
    @connection.assign_attributes(connection_params)
    apply_credentials

    respond_to do |format|
      if @connection.save
        format.html { redirect_to @connection, notice: 'Active Directory connection was successfully updated.' }
        format.json { head :no_content }
      else
        format.html { render action: 'edit' }
        format.json { render json: @connection.errors, status: :unprocessable_entity }
      end
    end
  end

  private

  def set_connection
    @connection = ActiveDirectoryConnection.find(params[:id])
  end

  # Neither password is permitted here. Both are handled by #apply_credentials,
  # and permitting them would let an untouched edit form blank a stored
  # credential -- the same trap as windows_targets#password.
  def connection_params
    params.require(:active_directory_connection)
          .permit(:name, :host, :port, :bind_dn, :search_base,
                  :polling_priority_id, :poll_username, :event_logs, :enabled)
  end

  # Sets each credential only when the form actually supplied one.
  def apply_credentials
    %i[password poll_password].each do |field|
      supplied = params.dig(:active_directory_connection, field)
      next if supplied.nil? || (supplied.respond_to?(:empty?) && supplied.empty?)
      @connection.public_send("#{field}=", supplied)
    end
  end
end

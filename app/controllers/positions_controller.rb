class PositionsController < ApplicationController
  before_action :set_position, only: [:show]

  # GET /positions
  # GET /positions.json
  def index
    @positions = Position.all.offset(0).limit(20)
  end

  # GET /positions/1
  # GET /positions/1.json
  def show
  end


end

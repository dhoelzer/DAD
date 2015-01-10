class WordsController < ApplicationController
  before_action :set_word, only: [:show]

  # GET /words
  # GET /words.json
  def index
    @words = Word.all.offset(0).limit(20)
  end

  # GET /words/1
  # GET /words/1.json
  def show
  end


  private
    # Use callbacks to share common setup or constraints between actions.
    def set_word
      @word = Word.find(params[:id])
    end

    # Never trust parameters from the scary internet, only allow the white list through.
    def word_params
      params.require(:word).permit(:text)
    end
end

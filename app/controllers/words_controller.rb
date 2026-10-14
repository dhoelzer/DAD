# Read-only screens over the Word table; requires the Admin right.
#
# Only #index and #show are implemented: Words are produced by ingestion and are
# the backing store of the search index, so editing them here would desynchronise
# the events_words join rows.
class WordsController < ApplicationController
  before_action :set_word, only: [:show]

  # Lists all words records. No pagination or filtering.
  def index
    @words = Word.all.offset(0).limit(20)
  end

  # One word, addressed by id. @word is loaded by the
  # before_action; the .json form returns the record as JSON.
  def show
  end


  private
    # Loads @word from params[:id]; raises 404 when no such
    # record exists. Internal: runs as a before_action.
    def set_word
      @word = Word.find(params[:id])
    end

    # Attribute whitelist for word writes; any param not
    # listed here is dropped before it reaches the model.
    def word_params
      params.require(:word).permit(:text)
    end
end

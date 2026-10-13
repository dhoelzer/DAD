# One distinct token extracted from event lines, and the unit of the search index.
#
# Event.storeEvent tokenises each line, maps every unique token to a Word row,
# and writes one events_words row per (event, word) pair. Searching is therefore
# a lookup of words by text followed by a scan of events_words.
class Word < ActiveRecord::Base
  has_and_belongs_to_many :events

  # Words are an implementation detail of the index; the tab is hidden even from
  # admins (the WordsController show action remains reachable by URL).
  def self.hidden?(current_user = nil)
    return true
  end

  # Returns the id of the Word whose text equals +new_word+, creating it if new.
  #
  # Callers (Event.storeEvent) want the id only, so the row is not returned.
  # Text longer than 255 characters is truncated and suffixed with "..." because
  # the column is a fixed-width string -- long tokens therefore collide on the
  # truncated form and are searched as a single word.
  def self.find_or_add(new_word)
    # Since we're using STRING fields, we must limit them to 255 characters each.  We lose some
    # fidelity here.
    new_word = new_word[0...(255-3)] + "..." if new_word.length > 255
    word=Word.find_by text: new_word
    if word.nil? then
      word = Word.create(:text => new_word)
    end
    return word.id
  end
end

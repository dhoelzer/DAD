class Word < ActiveRecord::Base
  has_many :positions
  has_many :events, :through => :positions
  
  def self.hidden?(current_user = nil)
    return true
  end
  
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

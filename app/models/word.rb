class Word < ActiveRecord::Base
  has_many :positions
  has_many :events, :through => :positions
  @@cached_words = Hash.new
  @added = 0
  
  def self.find_or_add(new_word)
    if @@cached_words.keys.include?(new_word) then
      @@cached_words[new_word][:last] = Time.now
      return @@cached_words[new_word][:id] 
    end
    word=Word.find_by text: new_word
    if word.nil? then
      word = Word.create(:text => new_word)
      @added += 1
    end
    @@cached_words[new_word] = {:id => word.id, :last => Time.now}
    self.prune_words if @@cached_words.keys.count > 50000
    return word.id
  end
  
  def self.number_of_cached_words
    return @@cached_words.keys.size
  end
  
  def self.added
    return @added
  end
  
  def self.prune_words
    @@cached_words = @@cached_words.select{|k,v| v[:last] > Time.now - 60 }
  end
end

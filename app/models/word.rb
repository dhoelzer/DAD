class Word < ActiveRecord::Base
  has_many :positions
  has_many :events, :through => :positions
  @@cached_words = Hash.new
  @added = 0
  @cache_hits = 0
  @@num_cached = 0
  CACHESIZE=10000
  @@cachelifetime=30
  
  def self.hidden?(current_user = nil)
    return true
  end
  
  def self.find_or_add(new_word)
    # Since we're using STRING fields, we must limit them to 255 characters each.  We lose some
    # fidelity here.
    new_word = new_word[0...(255-3)] + "..." if new_word.length > 255
    if @@cached_words.has_key?(new_word) then
      @@cached_words[new_word][:last] = Time.now
      @cache_hits += 1
      return @@cached_words[new_word][:id] 
    end
    word=Word.find_by text: new_word
    if word.nil? then
      word = Word.create(:text => new_word)
      @added += 1
    end
    @@num_cached += 1
    @@cached_words[new_word] = {:id => word.id, :last => Time.now}
    self.prune_words if @@num_cached > CACHESIZE
    return word.id
  end
  
  def self.number_of_cached_words
    return @@cached_words.size
  end
  
  def self.added
    return @added
  end
  
  def self.prune_words
    current_time = Time.now
    prune_time = current_time - @@cachelifetime
    @@cached_words = @@cached_words.select{|k,v| v[:last] > prune_time }
    pruned_count = CACHESIZE - @@cached_words.keys.count
    puts "\t+++ Pruned approximately #{pruned_count}."
    if pruned_count > (CACHESIZE / 3) then
      @@cachelifetime += 1
      puts "\t+++ Cache lifetime increased to #{@@cachelifetime}."
    else 
      @@cachelifetime -= 1
      puts "\t+++ Cache lifetime decreased to #{@@cachelifetime}."
    end
    puts "\t+++ There have been #{@cache_hits} hits in the word cache."
    @@num_cached = @@cached_words.keys.count
  end
end

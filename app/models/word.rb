# One distinct token extracted from event lines, and the unit of the search index.
#
# EventIngestor.storeEvent tokenises each line, maps every unique token to a Word row,
# and writes one events_words row per (event, word) pair. Searching is therefore
# a lookup of words by text followed by a scan of events_words.
class Word < ActiveRecord::Base
  has_and_belongs_to_many :events

  # Words are an implementation detail of the index; the tab is hidden even from
  # admins (the WordsController show action remains reachable by URL).
  def self.hidden?(current_user = nil)
    return true
  end

  # Tokens longer than this are stored truncated; see #truncate_for_column.
  COLUMN_WIDTH = 255

  # Round-trips used per bulk call. Bounds both the IN list and the INSERT, and
  # keeps a single statement well under the adapter parameter ceiling.
  RESOLVE_CHUNK = 2000

  # Lossy form a token is stored under. Text longer than the column is truncated
  # and suffixed with "..." because the column is a fixed-width string -- long
  # tokens therefore collide on the truncated form and are searched as a single
  # word. Every caller must map tokens through this before lookup, or a long
  # token would be looked up under one spelling and stored under another.
  def self.truncate_for_column(text)
    return text if text.length <= COLUMN_WIDTH
    text[0...(COLUMN_WIDTH - 3)] + "..."
  end

  # Returns {token => id} for every token in +tokens+, creating the missing rows.
  #
  # Two round-trips per RESOLVE_CHUNK tokens -- one indexed IN lookup for the
  # existing rows, one multi-row INSERT for the rest -- instead of one lookup and
  # one autocommit INSERT per token. Measured over 20k log lines with 46,450
  # distinct words: 92,900 statements and 46,450 transactions against the words
  # table become 60 statements and 30.
  #
  # +tokens+ are taken as-is and truncated for the column, so the returned keys
  # are the stored forms. Duplicate inputs collapse.
  #
  # insert_all is used rather than create because Word has no validations or
  # callbacks to run, and because per-row create pays a transaction commit each
  # time. RETURNING gives the new ids back without a second query; the re-pluck
  # below is the fallback for an adapter that does not return them, so a missing
  # id can never become a NULL word_id in events_words.
  def self.resolve_ids(tokens)
    return {} if tokens.empty?

    ids = {}
    tokens.map { |t| truncate_for_column(t) }.uniq.each_slice(RESOLVE_CHUNK) do |chunk|
      # words.text is not unique, so a text can have several rows. Keep the
      # lowest id: that is what the old per-token find_by returned, and a
      # pluck().to_h would silently keep the highest instead.
      found = {}
      where(text: chunk).order(:id).pluck(:text, :id).each { |text, id| found[text] ||= id }
      ids.merge!(found)

      missing = chunk.reject { |t| found.key?(t) }
      next if missing.empty?

      inserted = insert_all(missing.map { |t| { 'text' => t } }, returning: %i[id text])
      inserted.each do |row|
        text = row['text'] || row[:text]
        id = row['id'] || row[:id]
        ids[text] = id if text && id
      end

      still_missing = missing.reject { |t| ids.key?(t) }
      if still_missing.any?
        # RETURNING unsupported or short: the rows are committed either way, so
        # re-reading them is correct rather than a retry of the write.
        where(text: still_missing).order(:id).pluck(:text, :id).each do |text, id|
          ids[text] ||= id
        end
      end
    end
    ids
  end

  # Returns the id of the Word whose text equals +new_word+, creating it if new.
  #
  # Single-token form of #resolve_ids. Ingest uses the bulk form; this stays for
  # callers that have one token in hand.
  def self.find_or_add(new_word)
    resolve_ids([new_word]).values.first
  end
end

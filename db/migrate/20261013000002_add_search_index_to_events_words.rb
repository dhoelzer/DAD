class AddSearchIndexToEventsWords < ActiveRecord::Migration
  INDEX_NAME = 'index_events_words_on_word_id_and_generated_and_event_id'.freeze
  COLUMNS = %w[word_id generated event_id].freeze

  # CREATE INDEX CONCURRENTLY cannot run inside a transaction, and a plain
  # add_index would hold a write lock on events_words for the whole build,
  # which stalls ingestion on a table that grows by one row per token per event.
  disable_ddl_transaction!

  def up
    if index_algorithms.key?(:concurrently)
      add_index :events_words, COLUMNS, name: INDEX_NAME, algorithm: :concurrently
    else
      add_index :events_words, COLUMNS, name: INDEX_NAME
    end
  end

  def down
    remove_index :events_words, name: INDEX_NAME
  end
end

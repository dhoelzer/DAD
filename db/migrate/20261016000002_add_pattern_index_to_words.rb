# Byte-wise index over words.text, so prefix search stays index-driven on
# Postgres regardless of the database's collation.
#
# Postgres-only: SQLite's default BINARY collation already lets
# index_words_on_text serve the search predicate, and SQLite has no operator
# classes to specify.
#
# Why: Event.searchSQL matches terms as literal prefixes with
# `text like 'term%' escape '\'`. A plain index on words.text is ordered by the
# database collation, and the LIKE operator can only use it when the collation is
# byte-wise. On en_US.UTF-8 -- the postgres:17 default, and what provision.sh
# creates -- the planner falls back to a sequential scan of words.
# varchar_pattern_ops indexes raw bytes, so the LIKE can use it under any
# collation.
#
# The existing collation-ordered index is kept: Event.searchSQL also applies a
# `text >= term` lower bound, which SQLite uses to seek rather than scan.
class AddPatternIndexToWords < ActiveRecord::Migration[8.1]
  INDEX_NAME = 'index_words_on_text_pattern'.freeze

  # Same reasoning as AddSearchIndexToEventsWords: CONCURRENTLY cannot run in a
  # transaction, and a plain build would lock the table ingest inserts into.
  disable_ddl_transaction!

  def up
    return unless connection.adapter_name == 'PostgreSQL'

    # Safe to hard-code CONCURRENTLY here: the guard above means only Postgres
    # reaches this, and it always supports the algorithm.
    add_index :words, :text, name: INDEX_NAME,
                             opclass: :varchar_pattern_ops,
                             algorithm: :concurrently
  end

  def down
    return unless connection.adapter_name == 'PostgreSQL'

    connection.remove_index :words, name: INDEX_NAME
  end
end

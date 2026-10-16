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

    # A CONCURRENTLY build that fails -- lock timeout, deadlock, cancelled
    # statement -- does not roll back. Postgres keeps the half-built index as
    # INVALID, and it still occupies the name. Re-running this migration then
    # fails with `relation "index_words_on_text_pattern" already exists`, which
    # wedges `rake db:migrate` and with it provision.sh, because the deploy
    # re-runs the same migration. Drop the husk first so the retry rebuilds.
    #
    # Scoped deliberately: only an index this migration owns, and only one
    # Postgres itself reports as unusable. A valid index is never touched.
    if (name = invalid_index_named(INDEX_NAME))
      say_with_time "dropping INVALID index #{name} left by a failed CONCURRENTLY build" do
        remove_index :words, name: name, algorithm: :concurrently
      end
    end

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

  # Returns +index_name+ if an index by that name exists and Postgres marks it
  # invalid, otherwise nil.
  #
  # index_exists?/index_name_exists? cannot answer this: their query joins
  # pg_indexes/pg_class without filtering pg_index.indisvalid, so an INVALID
  # husk reads as a healthy index.
  def invalid_index_named(index_name)
    invalid = connection.select_value(
      'select not i.indisvalid from pg_class c ' \
      'join pg_index i on i.indexrelid = c.oid ' \
      "where c.relname = #{connection.quote(index_name)} and c.relkind = 'i'")
    invalid ? index_name : nil
  end
end

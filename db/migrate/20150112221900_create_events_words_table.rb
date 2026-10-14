class CreateEventsWordsTable < ActiveRecord::Migration[4.2]
  def change
    # Rails 6.1 raises "you can't define an already defined column" when a
    # create_join_table block re-declares the columns create_join_table already
    # emitted via references (5.2 allowed it and let the block win). The 8-byte
    # limit now goes through column_options; null: true keeps the columns
    # nullable, matching the pre-existing DDL.
    create_join_table :events, :words, column_options: { limit: 8, null: true }
  end
end

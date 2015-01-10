class AddIndices < ActiveRecord::Migration
  def change
    add_index :positions, :event_id
    add_index :words, :text
    add_index :positions, :word_id
  end
end

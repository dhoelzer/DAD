class AddIndices < ActiveRecord::Migration[4.2]
  def change
    add_index :words, :text
  end
end

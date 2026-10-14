class AddHunksToEvents < ActiveRecord::Migration[4.2]
  def change
    add_column :events, :hunks, :text
  end
end

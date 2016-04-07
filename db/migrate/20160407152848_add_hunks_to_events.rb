class AddHunksToEvents < ActiveRecord::Migration
  def change
    add_column :events, :hunks, :text
  end
end

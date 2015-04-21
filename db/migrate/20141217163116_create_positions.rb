class CreatePositions < ActiveRecord::Migration
  def change
    create_table :positions, :id => false do |t|
      t.integer :id, :limit => 8
      t.integer :word_id, :limit => 8
      t.integer :position
      t.integer :event_id, :limit => 8
    end
  end
end

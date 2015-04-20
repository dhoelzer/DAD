class CreatePositions < ActiveRecord::Migration
  def change
    create_table :positions do |t|
      t.index :word_id
      t.integer :position
      t.index :event_id
    end
  end
end

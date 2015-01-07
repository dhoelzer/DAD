class CreatePositions < ActiveRecord::Migration
  def change
    create_table :positions do |t|
      t.integer :word_id
      t.integer :position
      t.integer :event_id

      t.timestamps
    end
  end
end

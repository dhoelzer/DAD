class CreateExclusions < ActiveRecord::Migration[4.2]
  def change
    create_table :exclusions do |t|
      t.string :pattern
      t.integer :user_id

      t.timestamps null: false
    end
  end
end

class CreateExclusions < ActiveRecord::Migration
  def change
    create_table :exclusions do |t|
      t.string :pattern
      t.integer :user_id

      t.timestamps null: false
    end
  end
end

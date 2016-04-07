class CreateHunks < ActiveRecord::Migration
  def change
    create_table :hunks do |t|
      t.string :text, :limit => 32

      t.timestamps null: false
    end
    add_index :hunks, :text
  end
end

class CreateDisplays < ActiveRecord::Migration
  def change
    create_table :displays, :id => false do |t|
      t.integer :id, :limit => 8
      t.string :key
      t.integer :key_field
      t.string :name
      t.text :description

      t.timestamps
    end
  end
end

class CreateDisplays < ActiveRecord::Migration[4.2]
  def change
    create_table :displays do |t|
      t.string :key
      t.integer :key_field
      t.string :name
      t.text :description

      t.timestamps
    end
  end
end

class CreateDisplays < ActiveRecord::Migration
  def change
    create_table :displays do |t|
      t.string :key
      t.smallint :key_field
      t.string :name
      t.text :description

      t.timestamps
    end
  end
end

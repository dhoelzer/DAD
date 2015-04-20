class CreateDisplayFields < ActiveRecord::Migration
  def change
    create_table :display_fields do |t|
      t.index :display_id
      t.integer :field_position
      t.string :title
      t.integer :order

      t.timestamps
    end
  end
end

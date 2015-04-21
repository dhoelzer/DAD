class CreateDisplayFields < ActiveRecord::Migration
  def change
    create_table :display_fields do |t|
      t.integer :display_id, :limit => 8
      t.integer :field_position
      t.string :title
      t.integer :order

      t.timestamps
    end
  end
end

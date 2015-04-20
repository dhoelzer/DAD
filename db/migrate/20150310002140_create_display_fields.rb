class CreateDisplayFields < ActiveRecord::Migration
  def change
    create_table :display_fields do |t|
      t.integer :display_id
      t.smallint :field_position
      t.string :title
      t.smallint :order

      t.timestamps
    end
  end
end

class ReplaceDisplays < ActiveRecord::Migration
  def change
    drop_table :displays
    drop_table :display_fields
    create_table :displays do |t|
      t.string :key
      t.string :name
      t.text :description
      t.text :display_script
      t.integer :user_id
      t.timestamps
    end
    
  end
end

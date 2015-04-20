class CreateComments < ActiveRecord::Migration
  def change
    create_table :comments do |t|
      t.text :message
      t.integer :user_id
      t.index :alert_id

      t.timestamps
    end
  end
end

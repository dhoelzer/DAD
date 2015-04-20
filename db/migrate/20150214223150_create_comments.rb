class CreateComments < ActiveRecord::Migration
  def change
    create_table :comments do |t|
      t.text :message
      t.integer :user_id, :limit => 8
      t.integer :alert_id, :limit => 8

      t.timestamps
    end
  end
end

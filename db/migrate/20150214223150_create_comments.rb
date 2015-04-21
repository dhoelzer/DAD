class CreateComments < ActiveRecord::Migration
  def change
    create_table :comments, :id => false do |t|
      t.integer :id, :limit => 8
      t.text :message
      t.integer :user_id, :limit => 8
      t.integer :alert_id, :limit => 8

      t.timestamps
    end
  end
end

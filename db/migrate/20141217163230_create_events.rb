class CreateEvents < ActiveRecord::Migration
  def change
    create_table :events, :id => false do |t|
      t.integer :id, :limit => 8
      t.integer :system_id, :limit => 8
      t.integer :service_id, :limit => 8
      t.datetime :generated
      t.datetime :stored

      t.timestamps
    end
  end
end

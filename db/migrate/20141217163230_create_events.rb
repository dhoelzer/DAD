class CreateEvents < ActiveRecord::Migration
  def change
    create_table :events do |t|
      t.integer :system_id, :limit => 8
      t.integer :service_id, :limit => 8
      t.datetime :generated, :default => Time.now, :null => false
      t.datetime :stored

      t.timestamps
    end
  end
end

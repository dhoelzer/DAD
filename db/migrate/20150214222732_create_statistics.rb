class CreateStatistics < ActiveRecord::Migration
  def change
    create_table :statistics, :id => false do |t|
      t.integer :id, :limit => 8
      t.integer :type_id
      t.datetime :timestamp
      t.integer :system_id, :limit => 8
      t.integer :service_id, :limit => 8
      t.float :stat

      t.timestamps
    end
  end
end

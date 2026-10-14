class CreateStatistics < ActiveRecord::Migration[4.2]
  def change
    create_table :statistics do |t|
      t.integer :type_id
      t.datetime :timestamp
      t.integer :system_id, :limit => 8
      t.integer :service_id, :limit => 8
      t.float :stat

      t.timestamps
    end
  end
end

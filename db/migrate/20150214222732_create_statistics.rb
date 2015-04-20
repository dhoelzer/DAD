class CreateStatistics < ActiveRecord::Migration
  def change
    create_table :statistics do |t|
      t.integer :type_id
      t.datetime :timestamp
      t.index :system_id
      t.index :service_id
      t.float :stat

      t.timestamps
    end
  end
end

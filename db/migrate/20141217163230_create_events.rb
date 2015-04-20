class CreateEvents < ActiveRecord::Migration
  def change
    create_table :events do |t|
      t.index :system_id
      t.index :service_id
      t.datetime :generated
      t.datetime :stored

      t.timestamps
    end
  end
end

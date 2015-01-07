class CreateEvents < ActiveRecord::Migration
  def change
    create_table :events do |t|
      t.integer :system_id
      t.integer :service_id
      t.datetime :generated
      t.datetime :stored

      t.timestamps
    end
  end
end

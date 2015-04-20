class CreateEvents < ActiveRecord::Migration
  def change
    create_table :events do |t|
      t.bigint :system_id
      t.bigint :service_id
      t.datetime :generated
      t.datetime :stored

      t.timestamps
    end
  end
end

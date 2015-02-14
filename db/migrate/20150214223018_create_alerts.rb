class CreateAlerts < ActiveRecord::Migration
  def change
    create_table :alerts do |t|
      t.integer :system_id
      t.integer :service_id
      t.integer :criticality
      t.datetime :generated
      t.integer :event_id
      t.boolean :closed
      t.text :description
      t.string :short_description

      t.timestamps
    end
  end
end

class CreateAlerts < ActiveRecord::Migration
  def change
    create_table :alerts, :id => false do |t|
      t.integer :id, :limit => 8
      t.integer :system_id, :limit => 8
      t.integer :service_id, :limit => 8
      t.integer :criticality
      t.datetime :generated
      t.boolean :closed
      t.text :description
      t.string :short_description

      t.timestamps
    end
  end
end

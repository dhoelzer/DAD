class CreateAlerts < ActiveRecord::Migration
  def change
    create_table :alerts do |t|
      t.index :system_id
      t.index :service_id
      t.integer :criticality
      t.datetime :generated
      t.boolean :closed
      t.text :description
      t.string :short_description

      t.timestamps
    end
  end
end

class CreateAlertsEventsJointable < ActiveRecord::Migration
  def change
     create_join_table :alerts, :events do |t|
      t.integer :alert_id, :limit => 8
      t.integer :event_id, :limit => 8
    end
    add_index :alerts_events, :alert_id
  end
end

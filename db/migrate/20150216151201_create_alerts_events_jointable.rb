class CreateAlertsEventsJointable < ActiveRecord::Migration
  def change
     create_join_table :alerts, :events do |t|
      t.integer :alert_id
      t.integer :event_id
    end
  end
end

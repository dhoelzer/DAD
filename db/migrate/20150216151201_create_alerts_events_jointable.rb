class CreateAlertsEventsJointable < ActiveRecord::Migration
  def change
     create_join_table :alerts, :events do |t|
      t.index :alert_id
      t.index :event_id
    end
  end
end

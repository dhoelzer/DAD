class CreateAlertsEventsJointable < ActiveRecord::Migration[4.2]
  def change
     # See CreateEventsWordsTable: 6.1 rejects re-declaring the columns
     # create_join_table already emitted, so the limit moves to column_options.
     create_join_table :alerts, :events, column_options: { limit: 8, null: true }
    add_index :alerts_events, :alert_id
  end
end

class RemoveEventIdFromAlerts < ActiveRecord::Migration
  def change
    remove_column :alerts, :event_id
  end
end

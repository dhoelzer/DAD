class ConvertToBigint < ActiveRecord::Migration
  def change
    change_column :positions, :event_id, :bigint
    change_column :positions, :word_id, :bigint
    change_column :alerts_events, :alert_id, :bigint
    change_column :alerts_events, :event_id, :bigint
  end
end

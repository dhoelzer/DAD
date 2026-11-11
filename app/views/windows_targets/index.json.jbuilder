# Explicit field list rather than a whole-record extract: the model carries an
# encrypted password column, and json.extract! without a list would publish it.
json.array!(@windows_targets) do |target|
  json.extract! target, :id, :address, :name, :event_logs, :enabled, :username,
                :last_polled_at, :next_poll_at, :last_event_count, :poll_count, :last_status
  json.priority target.polling_priority.name
  json.display_name target.display_name
  json.url windows_target_url(target, format: :json)
end

json.extract! @windows_target, :id, :address, :name, :event_logs, :enabled, :username,
              :last_polled_at, :next_poll_at, :events_per_second, :last_event_count,
              :poll_count, :last_status, :created_at, :updated_at
json.priority @windows_target.polling_priority.name
json.display_name @windows_target.display_name
# Whether a credential exists, never the credential.
json.credential_present @windows_target.password.present?

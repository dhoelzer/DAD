json.extract! @connection, :id, :name, :host, :port, :bind_dn, :search_base,
              :event_logs, :poll_username, :enabled, :last_query_at, :last_status,
              :created_at, :updated_at
json.priority @connection.polling_priority.name
json.display_name @connection.display_name
# Whether credentials exist, never the credentials.
json.credential_present @connection.password.present?
json.polling_credential_present @connection.polling_credential_present?

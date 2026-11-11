# Explicit field list: the model carries two encrypted credential columns, and
# json.extract! without a list would publish their ciphertext.
json.array!(@connections) do |connection|
  json.extract! connection, :id, :name, :host, :port, :bind_dn, :search_base,
                :event_logs, :poll_username, :enabled, :last_query_at, :last_status
  json.priority connection.polling_priority.name
  json.display_name connection.display_name
  json.credential_present connection.password.present?
  json.polling_credential_present connection.polling_credential_present?
  json.url active_directory_connection_url(connection, format: :json)
end

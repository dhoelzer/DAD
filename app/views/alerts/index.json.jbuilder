json.array!(@alerts) do |alert|
  json.extract! alert, :id, :system_id, :service_id, :criticality, :generated, :event_id, :closed, :description, :short_description
  json.url alert_url(alert, format: :json)
end

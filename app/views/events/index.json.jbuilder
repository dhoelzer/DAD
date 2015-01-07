json.array!(@events) do |event|
  json.extract! event, :id, :system_id, :service_id, :generated, :stored
  json.url event_url(event, format: :json)
end

json.array!(@display_fields) do |display_field|
  json.extract! display_field, :id, :display_id, :field_position, :title, :order
  json.url display_field_url(display_field, format: :json)
end

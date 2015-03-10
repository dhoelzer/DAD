json.array!(@displays) do |display|
  json.extract! display, :id, :key, :key_field, :name, :description
  json.url display_url(display, format: :json)
end

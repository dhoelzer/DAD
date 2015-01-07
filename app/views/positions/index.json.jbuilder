json.array!(@positions) do |position|
  json.extract! position, :id, :word_id, :position, :event_id
  json.url position_url(position, format: :json)
end

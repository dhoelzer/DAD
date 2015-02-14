json.array!(@searches) do |search|
  json.extract! search, :id, :string, :user_id, :description, :short_description
  json.url search_url(search, format: :json)
end

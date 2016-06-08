json.array!(@exclusions) do |exclusion|
  json.extract! exclusion, :id, :pattern, :user_id
  json.url exclusion_url(exclusion, format: :json)
end

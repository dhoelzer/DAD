json.array!(@hunks) do |hunk|
  json.extract! hunk, :id, :text
  json.url hunk_url(hunk, format: :json)
end

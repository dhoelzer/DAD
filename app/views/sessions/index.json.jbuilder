json.array!(@sessions) do |session|
  json.extract! session, :id, :hash, :user_id, :expiry
  json.url session_url(session, format: :json)
end

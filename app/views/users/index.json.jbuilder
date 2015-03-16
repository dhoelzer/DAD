json.array!(@users) do |user|
  json.extract! user, :id, :username, :password, :first, :last, :lastlogon
  json.url user_url(user, format: :json)
end

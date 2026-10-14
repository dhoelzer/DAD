json.array!(@sessions) do |session|
  # :session_hash is deliberately not extracted. It is the sole bearer credential
  # gatekeeper accepts, so exposing it here would let anyone with the Sessions
  # right hijack the login. The previous :hash extracted Object#hash -- a random
  # integer, not the token.
  json.extract! session, :id, :user_id, :expiry
  json.url session_url(session, format: :json)
end

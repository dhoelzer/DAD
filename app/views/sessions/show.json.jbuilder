# :session_hash is omitted for the same reason as index.json.jbuilder: it is the
# bearer credential, not a display field. :hash previously extracted Object#hash.
json.extract! @session, :id, :user_id, :expiry, :created_at, :updated_at

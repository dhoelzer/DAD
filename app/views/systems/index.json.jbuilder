json.array!(@systems) do |system|
  json.extract! system, :id, :address, :name, :description, :administrator, :contact_email
  json.url system_url(system, format: :json)
end

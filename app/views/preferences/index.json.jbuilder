json.array!(@preferences) do |preference|
  json.extract! preference, :id, :user_id, :liveEventsDisplayed, :dashboardElements
  json.url preference_url(preference, format: :json)
end

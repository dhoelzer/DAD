json.array!(@jobs) do |job|
  json.extract! job, :id, :name, :description, :user_id, :script, :last_event_id, :last_run, :next_run, :frequency
  json.url job_url(job, format: :json)
end

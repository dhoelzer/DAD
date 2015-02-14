json.array!(@statistics) do |statistic|
  json.extract! statistic, :id, :type_id, :timestamp, :system_id, :service_id, :stat
  json.url statistic_url(statistic, format: :json)
end

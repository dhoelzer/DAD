# Shared reductions over hourly-bucketed series.
#
# The dashboard charts fetch a series once and then need several views of it: a
# chart series, a mean, and a mean/variance/stddev triple. Doing each reduction
# in SQL meant re-querying the same rows per view. These helpers take the
# [[bucket, value], ...] rows and reduce them in Ruby instead.
#
# A module rather than view helpers because the models build the same series;
# ApplicationHelper and System both use it.
module BucketStats
  # [[bucket, value], ...] reduced to [["M/D/YYYY H:00:00", n], ...], the shape the
  # charting library expects. Later buckets overwrite earlier ones for the same
  # label, matching the pre-existing behaviour.
  def self.series(buckets)
    data = Hash.new
    buckets.each do |bucket, value|
      data[ApplicationHelper.chart_label(bucket)] = value.to_i
    end
    data.map { |label, value| [label, value] }
  end

  # [mean, variance, standard deviation] over +buckets+. Empty input yields zeroes
  # via Stats rather than NaN.
  def self.summary(buckets)
    values = buckets.map { |_, value| value.to_i }
    [Stats.mean(values), Stats.variance(values), Stats.standard_deviation(values)]
  end
end

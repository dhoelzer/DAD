# Statistics helpers for the dashboard's baseline-vs-anomaly charts.
#
# These used to be defined on Ruby's core Math module from config/application.rb,
# which reopened it rather than shadowing it: Math.mean and friends became
# process-global, shared with every gem that touches Math. They now live here.
#
# Empty input returns 0.0 rather than NaN. NaN reached the .js.erb dashboards as
# `var stats = [NaN, NaN, NaN]`, which Highcharts turns into gauges with NaN
# axes; 0.0 renders, and draw_longitudinal already treats a zero standard
# deviation as "derive one from the mean".
module Stats
  # Arithmetic mean of +values+; 0.0 for an empty array.
  def self.mean(values)
    return 0.0 if values.empty?
    sum_values(values).to_f / values.count
  end

  # Mean squared deviation from the mean of +values+ (population variance,
  # dividing by n rather than n-1); 0.0 for an empty array.
  def self.variance(values)
    return 0.0 if values.empty?
    average = mean(values)
    sum = 0.0
    values.each { |s| sum += ((s - average)**2) }
    sum / values.count
  end

  # Square root of .variance for +values+.
  def self.standard_deviation(values)
    Math.sqrt(variance(values))
  end

  # Sum of +values+, accumulated with integer + so the result stays exact for
  # integer input.
  def self.sum_values(values)
    sum = 0
    values.each { |s| sum += s }
    sum
  end
end

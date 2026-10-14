require 'test_helper'

# Stats holds the dashboard's statistics helpers. They previously lived on
# Ruby's core Math module (config/application.rb reopened it); these tests
# cover both the arithmetic and the two reasons the old placement was wrong.
class StatsTest < ActiveSupport::TestCase
  test "mean, variance and standard_deviation match known values" do
    # [10, 20, 30]: mean 20, population variance 200/3, sd sqrt(200/3).
    assert_in_delta 20.0, Stats.mean([10, 20, 30]), 1e-9
    assert_in_delta 200.0 / 3, Stats.variance([10, 20, 30]), 1e-9
    assert_in_delta Math.sqrt(200.0 / 3), Stats.standard_deviation([10, 20, 30]), 1e-9
  end

  # Population variance (divide by n), not sample variance (n-1). The charts
  # describe the observed window rather than inferring a wider one, so this is
  # deliberate; pinned so a future refactor does not quietly switch it.
  test "variance is population variance, not sample variance" do
    # mean 5, squared deviations sum to 32: /8 = 4.0, whereas /7 would be ~4.57.
    assert_in_delta 4.0, Stats.variance([2, 4, 4, 4, 5, 5, 7, 9]), 1e-9
    refute_in_delta 32.0 / 7, Stats.variance([2, 4, 4, 4, 5, 5, 7, 9]), 1e-9
  end

  test "a single value has zero spread" do
    assert_in_delta 5.0, Stats.mean([5]), 1e-9
    assert_in_delta 0.0, Stats.variance([5]), 1e-9
    assert_in_delta 0.0, Stats.standard_deviation([5]), 1e-9
  end

  # The empty case is what produced `var stats = [NaN, NaN, NaN]` in the
  # .js.erb dashboards, which Highcharts drew as gauges with NaN axes.
  test "empty input returns zero rather than NaN" do
    assert_equal 0.0, Stats.mean([])
    assert_equal 0.0, Stats.variance([])
    assert_equal 0.0, Stats.standard_deviation([])
    refute Stats.mean([]).nan?
  end

  test "sum_values keeps integer input exact" do
    assert_equal 6, Stats.sum_values([1, 2, 3])
    assert_equal 0, Stats.sum_values([])
  end

  # The regression that motivated the move: these four methods were defined on
  # Ruby's core Math module, making them process-global for every gem.
  test "core Math is not extended with the app's helpers" do
    refute Math.respond_to?(:mean)
    refute Math.respond_to?(:variance)
    refute Math.respond_to?(:standard_deviation)
    refute Math.respond_to?(:sum_values)
  end

  test "core Math still works" do
    assert_in_delta 4.0, Math.sqrt(16), 1e-9
    assert_in_delta 1.0, Math.sin(Math::PI / 2), 1e-9
  end

  # Stats lives in app/models, which application.rb requires into $_models for
  # the nav bar; every entry there must answer hidden?. A module would not.
  test "Stats is not treated as a nav-bar model" do
    refute_includes $_models, 'Stats'
  end
end

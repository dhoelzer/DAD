require 'test_helper'
require 'open3'
require 'json'

# dad_charts.js registers dadBands and dadGauge globally with Chart.js, so both
# plugins run for *every* chart on the dashboard, not just the ones that ask for
# them. Chart.js still hands an unconfigured plugin a truthy options proxy, so a
# plugin cannot use `if (!opts)` to decide whether it applies -- it has to check
# the fields it actually needs.
#
# This runs the real plugin code under node rather than asserting against the
# source text, so it catches behaviour rather than spelling.
class DadChartsTest < ActiveSupport::TestCase
  CHARTS_JS = Rails.root.join('app/assets/javascripts/dad_charts.js')

  # Loads dad_charts.js with Chart.register stubbed, then calls the plugin hook
  # with a recording canvas context. Prints the drawing calls as JSON.
  HARNESS = <<~'JS'
    const fs = require('fs');
    global.Chart = { register() {}, defaults: {} };
    (0, eval)(fs.readFileSync(process.argv[2], 'utf8') + '\n;global.__p = dadGauge;');

    const ops = [];
    const ctx = {
      save() {}, restore() {}, beginPath() {}, closePath() {}, moveTo() {},
      lineTo() {}, stroke() {}, fill() {},
      arc(x, y, r) { ops.push('arc:' + r); },
      fillText(t, x, y) { ops.push('text:' + t + '@' + x + ',' + y); }
    };

    // A pie arc: innerRadius 0, so arc.x/arc.y is the centre of the pie.
    const pieArc = { x: 200, y: 150, innerRadius: 0, outerRadius: 100,
                     startAngle: -Math.PI / 2, endAngle: Math.PI * 1.5 };
    const pie = { ctx: ctx, getDatasetMeta: () => ({ data: [pieArc] }) };

    // What Chart.js passes to a globally registered plugin the chart never
    // configured: an object, so truthy, that yields undefined for every field.
    const unconfigured = new Proxy({}, { get(t, k) { return k in t ? t[k] : undefined; } });
    __p.afterDatasetsDraw(pie, {}, unconfigured);
    const onPie = ops.slice();

    // A gauge arc: the doughnut track, cutout 25%.
    ops.length = 0;
    const gaugeArc = { x: 200, y: 150, innerRadius: 25, outerRadius: 100,
                       startAngle: -Math.PI * 5 / 6, endAngle: Math.PI * 5 / 6 };
    const gauge = { ctx: ctx, getDatasetMeta: () => ({ data: [gaugeArc] }) };
    __p.afterDatasetsDraw(gauge, {}, {
      value: 1234, min: 0, max: 3000,
      bands: [{ from: 100, to: 900, color: '#a0a010' }]
    });
    const onGauge = ops.slice();

    // A quiet system has 0 events in the last hour, so 0 is a real reading and
    // must not be treated as "not configured".
    ops.length = 0;
    __p.afterDatasetsDraw(gauge, {}, { value: 0, min: 0, max: 1, bands: [] });

    console.log(JSON.stringify({ onPie: onPie, onGauge: onGauge, onZero: ops }));
  JS

  setup do
    skip 'node is required to exercise dad_charts.js' unless system('command -v node > /dev/null 2>&1')
  end

  def draw_ops
    script = Rails.root.join('tmp', 'dad_charts_harness.js')
    File.write(script, HARNESS)
    out, err, status = Open3.capture3('node', script.to_s, CHARTS_JS.to_s)
    assert_predicate status, :success?, "node failed running the plugin harness: #{err}"
    JSON.parse(out)
  ensure
    script&.delete
  end

  # The bug: dadGauge ran on the two 24-hour pies. opts.value was undefined,
  # String(undefined) is "undefined", and a pie arc has innerRadius 0, so it
  # landed dead centre. The needle was invisible because its angle came out NaN,
  # which is why the stray text and hub dot were the only visible damage.
  test 'dadGauge draws nothing on a chart that never configured it' do
    on_pie = draw_ops.fetch('onPie')

    assert_empty on_pie,
                 'dadGauge painted on a pie that never set plugins.dadGauge: ' \
                 "#{on_pie.inspect}"
  end

  # The guard must not disable the gauges it exists for.
  test 'dadGauge still draws the reading, hub and band for a gauge' do
    on_gauge = draw_ops.fetch('onGauge')

    assert_includes on_gauge, 'text:1234@200,163.75',
                    'the gauge reading is missing: ' + on_gauge.inspect
    assert_includes on_gauge, 'arc:4', 'the gauge hub is missing'
    assert_includes on_gauge, 'arc:62.5', 'the sigma band is missing'
  end

  # 0 is a reading, not an absent option. A guard written as `!opts.value` would
  # blank the gauge for every system that logged nothing in the last hour.
  test 'dadGauge still draws a gauge whose reading is zero' do
    on_zero = draw_ops.fetch('onZero')

    assert_includes on_zero, 'text:0@200,163.75',
                    'a zero reading was treated as unconfigured: ' + on_zero.inspect
  end
end

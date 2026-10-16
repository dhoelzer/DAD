// Chart primitives for the dashboard, on Chart.js (MIT, vendored under
// vendor/assets/javascripts/chartjs). This replaces Highcharts 4.0.4, which was
// a commercial-licensed vendored copy from 2014.
//
// Chart.js has no equivalent of Highcharts' yAxis.plotBands / plotLines, and no
// gauge series at all, so those are implemented here as plugins. The five
// draw_* entry points keep their Highcharts names and argument lists: the
// .js.erb templates and the dashboard tests call them by name.

// Horizontal threshold bands and rules on a linear y axis.
//
// Highcharts drew these from the axis; here they come from
// options.plugins.dadBands = {bands: [{from,to,color}], lines: [{value,color,width}]}.
// Drawn before the datasets so the series line stays on top, matching the
// Highcharts zIndex ordering the dashboard relied on.
var dadBands = {
  id: 'dadBands',
  beforeDatasetsDraw: function (chart, _args, opts) {
    if (!opts) { return; }
    var area = chart.chartArea, scale = chart.scales.y, ctx = chart.ctx;
    if (!area || !scale) { return; }

    ctx.save();
    (opts.bands || []).forEach(function (band) {
      var top = scale.getPixelForValue(band.to);
      var bottom = scale.getPixelForValue(band.from);
      // Clip to the plot area and drop bands that fall entirely outside it;
      // Highcharts omitted them rather than painting over the axis.
      if (bottom < area.top || top > area.bottom) { return; }
      top = Math.max(top, area.top);
      bottom = Math.min(bottom, area.bottom);
      ctx.fillStyle = band.color;
      ctx.fillRect(area.left, top, area.right - area.left, bottom - top);
    });
    (opts.lines || []).forEach(function (line) {
      var y = scale.getPixelForValue(line.value);
      if (y < area.top || y > area.bottom) { return; }
      ctx.strokeStyle = line.color;
      ctx.lineWidth = line.width;
      ctx.beginPath();
      ctx.moveTo(area.left, y);
      ctx.lineTo(area.right, y);
      ctx.stroke();
    });
    ctx.restore();
  }
};

// Gauge geometry: a 300-degree arc spanning -150 to +150, the Highcharts pane
// the dashboard used. Chart.js measures rotation from 12 o'clock and derives
// startAngle as toRadians(rotation - 90), so rotation -150 with circumference
// 300 reproduces it exactly.
var GAUGE_ROTATION = -150;
var GAUGE_SWEEP = 300;

// Canvas angle (radians, 0 at 3 o'clock) for a value on the gauge.
//
// Uses the arc element's own start/end angles rather than recomputing them, so
// the needle and bands cannot drift from the arc that was actually drawn.
function dadGaugeAngle(arc, min, max, value) {
  var fraction = (value - min) / (max - min);
  fraction = Math.max(0, Math.min(1, fraction));
  return arc.startAngle + (arc.endAngle - arc.startAngle) * fraction;
}

// The gauge itself: coloured threshold arcs, a needle, and the reading.
//
// Chart.js has no gauge series, so the chart is a doughnut whose arc is only a
// track; everything the dashboard showed is drawn by this plugin from
// options.plugins.dadGauge = {value, min, max, bands: [{from,to,color}]}.
//
// Both bands and needle draw *after* the datasets: unlike the longitudinal
// chart's bands, these sit on the outside of the arc, and drawing them first
// lets the track fill paint over them.
var dadGauge = {
  id: 'dadGauge',
  afterDatasetsDraw: function (chart, _args, opts) {
    if (!opts) { return; }
    var arc = chart.getDatasetMeta(0).data[0];
    if (!arc) { return; }
    var ctx = chart.ctx;
    var inner = arc.innerRadius, outer = arc.outerRadius;

    ctx.save();
    (opts.bands || []).forEach(function (band) {
      var from = dadGaugeAngle(arc, opts.min, opts.max, band.from);
      var to = dadGaugeAngle(arc, opts.min, opts.max, band.to);
      ctx.beginPath();
      ctx.strokeStyle = band.color;
      // Stroke at the mid-radius with the band's full thickness: an annulus
      // sector without the path arithmetic.
      ctx.lineWidth = outer - inner;
      ctx.arc(arc.x, arc.y, (inner + outer) / 2, from, to);
      ctx.stroke();
    });
    ctx.restore();

    var angle = dadGaugeAngle(arc, opts.min, opts.max, opts.value);

    ctx.save();
    ctx.strokeStyle = '#333399';
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(arc.x, arc.y);
    ctx.lineTo(arc.x + Math.cos(angle) * arc.outerRadius * 0.92,
               arc.y + Math.sin(angle) * arc.outerRadius * 0.92);
    ctx.stroke();

    ctx.fillStyle = '#333399';
    ctx.beginPath();
    ctx.arc(arc.x, arc.y, 4, 0, Math.PI * 2);
    ctx.fill();

    ctx.fillStyle = '#000000';
    ctx.font = '12px sans-serif';
    ctx.textAlign = 'center';
    ctx.fillText(String(opts.value), arc.x, arc.y + arc.innerRadius * 0.55);
    ctx.restore();
  }
};

Chart.register(dadBands, dadGauge);

// Returns a canvas in +div_id+, reusing and resetting the previous chart.
//
// The dashboard re-runs the draw_* functions every 60 seconds against the same
// divs. Highcharts replaced whatever was in renderTo; Chart.js refuses a canvas
// that already backs a chart, so the old instance has to be destroyed first.
// The first call also clears the spinner <img> the system page leaves behind.
function dad_prepare_canvas(div_id) {
  var div = document.getElementById(div_id);
  if (!div) { return null; }
  // Chart.js sizes to the container, so it needs the height the stylesheet
  // gives this class; Highcharts brought its own.
  div.classList.add('dad-chart');
  var canvas = div.querySelector('canvas');
  if (canvas) {
    var existing = Chart.getChart(canvas);
    if (existing) { existing.destroy(); }
  } else {
    div.innerHTML = '';
    canvas = document.createElement('canvas');
    div.appendChild(canvas);
  }
  return canvas;
}

// Chart.js sizes to its container, unlike Highcharts which defaulted to 400px,
// and animates by default, which the dashboard turned off because the charts
// redraw every 60 seconds. Applied globally so the draw_* helpers stay short;
// the stylesheet gives the chart divs their height.
Chart.defaults.responsive = true;
Chart.defaults.maintainAspectRatio = false;
Chart.defaults.animation = false;

// Drag a range on the x axis to zoom it; double-click restores.
//
// Replaces Highcharts' chart.zoomType = 'x'. Kept to the x axis, as it was.
function dad_enable_x_zoom(chart) {
  var canvas = chart.canvas;
  var scale = chart.scales.x;
  var fullMin = scale.min;
  var fullMax = scale.max;
  var dragStart = null;

  canvas.addEventListener('mousedown', function (event) {
    dragStart = chart.scales.x.getValueForPixel(event.offsetX);
  });
  canvas.addEventListener('mouseup', function (event) {
    if (dragStart === null) { return; }
    var start = dragStart;
    dragStart = null;
    var end = chart.scales.x.getValueForPixel(event.offsetX);
    var from = Math.min(start, end), to = Math.max(start, end);
    // A drag of under one category is a click, not a zoom.
    if (to - from < 1) { return; }
    chart.options.scales.x.min = from;
    chart.options.scales.x.max = to;
    chart.update();
  });
  canvas.addEventListener('dblclick', function () {
    chart.options.scales.x.min = fullMin;
    chart.options.scales.x.max = fullMax;
    chart.update();
  });
}

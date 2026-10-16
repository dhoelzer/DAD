// This is a manifest file that'll be compiled into application.js, which will include all the files
// listed below.
//
// Any JavaScript/Coffee file within this directory, lib/assets/javascripts, vendor/assets/javascripts,
// or vendor/assets/javascripts of plugins, if any, can be referenced here using a relative path.
//
// It's not advisable to add code directly here, but if you do, it'll appear at the bottom of the
// compiled file.
//
// Read Sprockets README (https://github.com/sstephenson/sprockets#sprockets-directives) for details
	// about supported directives.
	//
	// jquery3 (3.7.0), not jquery (1.12.4): CVE-2020-11023 / CVE-2020-23064 are
	// jQuery core XSS, fixed only in jQuery 3.5.0. Chart.js attaches no jQuery
	// event adapters, so the .bind/.unbind shim the old Highcharts adapter needed
	// is gone with it.
	//= require jquery3
	//= require jquery_ujs
	//= require turbolinks
	//= require chartjs/chart.umd
	//= require dad_charts
	//= require codemirror
	//= require codemirror/modes/ruby
	//= require_tree .

	// The five draw_* helpers below are the dashboard's chart API. They keep the
	// names and argument lists they had under Highcharts, because the .js.erb
	// templates call them positionally. dad_charts.js registers the Chart.js
	// plugins that supply the bands, rules and gauge the old library had built in.

	// Hourly series with the mean and its 1- and 2-sigma bands: the dashboard's
	// baseline-vs-anomaly view.
	function draw_longitudinal(chart_div, title, data_title, graph_data, average, standard_deviation)
	{
		if(standard_deviation==0) {
			standard_deviation = average * 0.20;
		};
		var canvas = dad_prepare_canvas(chart_div);
		if(!canvas) { return null; }

		var labels = graph_data.map(function (point) { return point[0]; });
		var values = graph_data.map(function (point) { return point[1]; });

		// Highcharts paired tickInterval 24 with labels.step 2, printing a label
		// every 48 categories; Chart.js has no step, so blank the skipped ones.
		var label_stride = 48;

		var chart = new Chart(canvas, {
			type: 'line',
			data: {
				labels: labels,
				datasets: [{
					label: data_title,
					data: values,
					borderColor: '#ff1010',
					borderWidth: 1,
					// Highcharts hid markers on series this dense.
					pointRadius: 0,
					tension: 0
				}]
			},
			options: {
				plugins: {
					title: { display: !!title, text: title },
					legend: { display: true },
					dadBands: {
						bands: [
							{
								color: '#ffffa0',
								from: (average - (2 * standard_deviation)),
								to: (average + (2 * standard_deviation))
							},
							{
								color: '#a0ffa0',
								from: (average - standard_deviation),
								to: (average + standard_deviation)
							}
						],
						lines: [
							{
								color: 'green',
								value: average,
								width: 2
							}
						]
					}
				},
				scales: {
					x: {
						type: 'category',
						ticks: {
							autoSkip: false,
							maxRotation: 90,
							minRotation: 90,
							callback: function (_value, index) {
								return index % label_stride === 0 ? labels[index] : '';
							}
						}
					},
					y: {
						min: (average - (2*standard_deviation) > 0 ? 0 : average - (2.1 * standard_deviation))
					}
				}
			}
		});
		dad_enable_x_zoom(chart);
		return chart;
	}

	// Root filesystem usage as a two-slice pie.
	function draw_diskspace_graph(chart_div, title, graph_data)
	{
		var canvas = dad_prepare_canvas(chart_div);
		if(!canvas) { return null; }

		return new Chart(canvas, {
			type: 'pie',
			data: {
				labels: graph_data.map(function (point) { return point[0]; }),
				datasets: [{
					label: "Disk Percentage:",
					data: graph_data.map(function (point) { return point[1]; }),
					backgroundColor: ['#ff1010', '#10ff10']
				}]
			},
			options: {
				plugins: {
					title: { display: !!title, text: title },
					legend: { display: true }
				}
			}
		});
	}

	// Event counts by system or service as a pie.
	function draw_graph(chart_div, title, graph_data)
	{
		var canvas = dad_prepare_canvas(chart_div);
		if(!canvas) { return null; }

		return new Chart(canvas, {
			type: 'pie',
			data: {
				labels: graph_data.map(function (point) { return point[0]; }),
				datasets: [{
					label: "Events Online:",
					data: graph_data.map(function (point) { return point[1]; })
				}]
			},
			options: {
				plugins: {
					title: { display: !!title, text: title },
					legend: { display: true }
				}
			}
		});
	}

	// Gauge options shared by the two gauge entry points.
	//
	// The doughnut is only the track: its single slice spans the whole 300-degree
	// sweep, and the dadGauge plugin draws the sigma bands, needle and reading
	// over it.
	function dad_gauge_config(title, graph_data, average, standard_deviation)
	{
		var max = Math.floor(average + (3*standard_deviation));
		// An install with no statistics yields average 0, which would make the
		// axis 0..0 and divide by zero when placing the needle.
		if (max <= 0) { max = 1; }

		return {
			type: 'doughnut',
			data: {
				labels: [''],
				datasets: [{
					label: "Logging Rate",
					data: [max],
					backgroundColor: '#f4f6f8',
					borderColor: '#333399',
					borderWidth: 1
				}]
			},
			options: {
				rotation: GAUGE_ROTATION,
				circumference: GAUGE_SWEEP,
				// Highcharts drew the bands from 25% to 105% of the pane radius;
				// cutout is the inner edge of the track.
				cutout: '25%',
				plugins: {
					title: { display: !!title, text: title },
					legend: { display: false },
					tooltip: { enabled: false },
					dadGauge: {
						value: graph_data,
						min: 0,
						max: max,
						bands: [{
							from: (average - (2*standard_deviation)),
							to: (average + (2*standard_deviation)),
							color: '#a0a010'
						},
						{
							from: (average - standard_deviation),
							to: (average + standard_deviation),
							color: '#10a010'
						}]
					}
				}
			}
		};
	}

	function draw_gauge(chart_div, title, graph_data, average, standard_deviation)
	{
		var canvas = dad_prepare_canvas(chart_div);
		if(!canvas) { return null; }
		return new Chart(canvas, dad_gauge_config(title, graph_data, average, standard_deviation));
	}

	function draw_gauge_no_title(chart_div, graph_data, average, standard_deviation)
	{
		var canvas = dad_prepare_canvas(chart_div);
		if(!canvas) { return null; }
		return new Chart(canvas, dad_gauge_config("", graph_data, average, standard_deviation));
	}

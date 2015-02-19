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
//= require jquery
//= require jquery_ujs
//= require turbolinks
//= require highcharts-custom.js
//= require_tree .

function draw_longitudinal(chart_div, title, data_title, graph_data)
{
	return new Highcharts.Chart({
		chart: {
			renderTo: chart_div,
			animation: false,
			zoomType: 'x',
		},
		colors: ['#ff1010', '#10ff10'],
		credits: {
			enabled: false
		},
		title: {
			text: title
		},
		plotOptions: {
			series: {
				animation: false,
				turboThreshold: 0,
			},
		},
		series: [
		{
			type: "line",
			name: data_title,
			data: graph_data,
			lineWidth: 1,
		}
		],
		xAxis: {
			labels: { step: 10, },
			type: "category",
		},
		yAxis: {
			floor: 0,
		}
	});

}

function draw_diskspace_graph(chart_div, title, graph_data)
{
   return new Highcharts.Chart({
      chart: {
        renderTo: chart_div,
		animation: false,
      },
	 colors: ['#ff1010', '#10ff10'],
	 credits: {
	    enabled: false
	  },
      title: {
        text: title
      },
	  plotOptions: {
		series: {
			animation: false,
		}
	},
      series: [
        {
          type: "pie",
          name: "Disk Percentage:",
          data: graph_data,
		  dataLabels: false,
        }
      ]
    });
}
 
function draw_graph(chart_div, title, graph_data)
{
   return new Highcharts.Chart({
      chart: {
        renderTo: chart_div,
		animation: false,
      },
	 credits: {
	    enabled: false
	  },
      title: {
        text: title
      },
	  plotOptions: {
		series: {
			animation: false,
		}
	},
      series: [
        {
          type: "pie",
          name: "Events Online:",
          data: graph_data,
		  dataLabels: false
        }
      ]
    });
}
	
function draw_gauge(chart_div, title, graph_data, timeframe)
{
   return new Highcharts.Chart({
      chart: {
        renderTo: chart_div,
		animation: false,
      },
	 credits: {
	    enabled: false,
	  },
      title: {
        text: title
      },
	  pane: {
		startAngle: -150,
		endAngle: 150
	  },
	  plotOptions: {
		series: {
			animation: false,
		}
	},
	  yAxis: {
		min: 0,
		max: (average_events * timeframe + (average_events * .1)),
		minorTickInterval: 'auto',
		minorTickWidth:1,
		minorTickLength: 10,
		minorTickPosition: 'inside',
		tickPixelInterval: ((average_events * .1) / 20),
		tickWidth: 2,
		tickPosition: 'inside',
		tickLength: 10,
		tickColor: '#555',
		labels: {
			step: (average_events * .1)/10,
			rotation: 'auto'
		}
	},
      series: [
        {
          type: "gauge",
          name: "Logging Rate",
          data: [graph_data]
        }
      ]
    });
}
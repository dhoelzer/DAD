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
	
function loading()
{
	var spinner=document.getElementById("spinner");
	if(spinner!==null && spinner!==undefined) { spinner.style.display="none";};
	var links=document.getElementById("searchload");
	if(links !== null && links !== undefined) {
		for(var i=0;i<links.length;i++){
			links[i].onclick = function() {document.getElementById("spinner").style.display="inline";}
		};
	};
};
		 
function draw_graph(chart_div, title, graph_data)
{
   return new Highcharts.Chart({
      chart: {
        renderTo: chart_div
      },
	 credits: {
	    enabled: false
	  },
      title: {
        text: title
      },
      series: [
        {
          type: "pie",
          name: "Events Online:",
          data: graph_data
        }
      ]
    });
}
	
function draw_gauge(chart_div, title, graph_data, timeframe)
{
   return new Highcharts.Chart({
      chart: {
        renderTo: chart_div
      },
	 credits: {
	    enabled: false
	  },
      title: {
        text: title
      },
	  pane: {
		startAngle: -150,
		endAngle: 150
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
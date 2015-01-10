# Place all the behaviors and hooks related to the matching controller here.
# All this logic will automatically be available in application.js.
# You can use CoffeeScript in this file: http://coffeescript.org/

draw_graph  =  (graph_data) ->
	alert(graph_data)
	new Highcharts.Chart({
		chart:
			renderTo: "big_picture_chart",
		title:
			text: "Big Picture",
		series:
			[{
				type: "pie",
				name: "Aggregate Events",
				data: graph_data
			}]
	})

results = (data, code, xhr)->
	alert(code)
	
big_picture = ->
	$("#big_picture_chart").html("Loading...")
	jQuery.ajax({
		type:'GET',
		url:'/events.js',
		dataType: 'script',
		complete: results
	})

$(document).ready(big_picture)
$(document).on('page:load', big_picture)

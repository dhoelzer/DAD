# Place all the behaviors and hooks related to the matching controller here.
# All this logic will automatically be available in application.js.
# You can use CoffeeScript in this file: http://coffeescript.org/
big_picture = ->
	jQuery.ajax({
		type:'GET',
		url:'/events',
		dataType: 'script'
	});
	new Highcharts.Chart({
		chart:
			renderTo: "big_picture_chart",
		title:
			text: "Big Picture"
		series:
			[{
				type: "pie",
				name: "Aggregate Events",
				data: [["Test 1", 12], ["Test 2", 20], ["Test 3", 29]]
			}]
	})
	


$(document).ready(big_picture)
$(document).on('page:load', big_picture)

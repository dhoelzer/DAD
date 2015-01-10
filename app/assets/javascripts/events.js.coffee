# Place all the behaviors and hooks related to the matching controller here.
# All this logic will automatically be available in application.js.
# You can use CoffeeScript in this file: http://coffeescript.org/

$(document).ready(big_picture)
$(document).on('page:load', big_picture)

big_picture = ->
	new Highcharts.Chart({
		chart:
			renderTo: "big_picture_chart",
			type: "pie"
		title:
			text: "Big Picture"
		xAxis:
			categories: ["KO-VPN", "KO-BNB", "KO-DB"]
		yAxis:
			min: 0,
			title: "Events"
		series:
			{
				name: "Aggregate Events",
				data: [ 3000, 5000, 10000]
			}
	})
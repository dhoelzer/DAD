# Place all the behaviors and hooks related to the matching controller here.
# All this logic will automatically be available in application.js.
# You can use CoffeeScript in this file: http://coffeescript.org/
big_picture = ->
	new Highcharts.Chart({
		chart:
			renderTo: "big_picture_chart",
		title:
			text: "Big Picture"
		series:
			[{
				type: "pie",
				name: "Aggregate Events",
				data: [ ['KO-VPN', 3000], ['KO-DNS', 5000], ['KO-MAIL', 10000]]
			}]
	})
	
$(document).ready(big_picture)
$(document).on('page:load', big_picture)


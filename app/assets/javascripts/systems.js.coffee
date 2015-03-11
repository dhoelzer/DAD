# Place all the behaviors and hooks related to the matching controller here.
# All this logic will automatically be available in application.js.
# You can use CoffeeScript in this file: http://coffeescript.org/


draw_gauges = ->
	jQuery.ajax({
		type:'GET',
		url:'/systems.js',
		dataType: 'script',
		complete: $.ajax()
		})
	
setupSystems = ->
	if($("#system-gauges").length)
		draw_gauges()
	
$(document).ready(setupSystems)
$(document).on('page:load', setupSystems)

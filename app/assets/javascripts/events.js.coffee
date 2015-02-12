# Place all the behaviors and hooks related to the matching controller here.
# All this logic will automatically be available in application.js.
# You can use CoffeeScript in this file: http://coffeescript.org/


results = (data, code, xhr)->
	#alert(code)
	{}

big_picture = ->
	$("#spinner").show()
	jQuery.ajax({
		type:'GET',
		url:'/events.js',
		dataType: 'script',
		complete: $.ajax()
		})

spinner = ->
	if($("#spinner").length)
		$("#spinner").hide()
	if($("#searchload").length)
		$("*[id*=searchload]").each ->
			$(this).click ->
				$("#spinner").show()
	
setup = ->
	$("#spinner").show()
	spinner()
	big_picture()
	
$(document).ready(setup)
$(document).on('page:load', setup)

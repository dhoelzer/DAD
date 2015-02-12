# Place all the behaviors and hooks related to the matching controller here.
# All this logic will automatically be available in application.js.
# You can use CoffeeScript in this file: http://coffeescript.org/


results = (data, code, xhr)->
	#alert(code)
	{}

big_picture = ->
		$('#spinner').show()
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
				$('#stats').html("<h2>Retrieving results...<img src='/assets/spinner.gif'></h2>")
				$("#spinner").show()
	
setup = ->
	spinner()
	big_picture()
$(document).ready(setup)
$(document).on('page:load', setup)

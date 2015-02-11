# Place all the behaviors and hooks related to the matching controller here.
# All this logic will automatically be available in application.js.
# You can use CoffeeScript in this file: http://coffeescript.org/


results = (data, code, xhr)->
	#alert(code)
	{}

big_picture = ->
		if ($('#big_picture').length)
			$('#big_picture').html("<h2>Loading...</h2>")
			jQuery.ajax({
				type:'GET',
				url:'/events.js',
				dataType: 'script',
				complete: results
				})

$(document).ready ->
	$("#spinner").hide()
	if($("#searchload"))
		$("#searchload").onclick ->
			$("#spinner").show()
		
$(document).ready(big_picture)
$(document).on('page:load', big_picture)
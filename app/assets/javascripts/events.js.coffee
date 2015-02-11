# Place all the behaviors and hooks related to the matching controller here.
# All this logic will automatically be available in application.js.
# You can use CoffeeScript in this file: http://coffeescript.org/


results = (data, code, xhr)->
	#alert(code)
	{}

loading = ->
	spinner=document.getElementById("spinner")
	links=document.getElementsByName("searchload")
	if(links !== null && links !== undefined) {
		for(i=0;i<links.length;i++){
			links[i].onclick = function() {document.getElementById("spinner").style.display="inline";}
		}
	}
	if(spinner!==null && spinner!==undefined) { spinner.style.display="none";}

		
big_picture = ->
		if ($('#big_picture').length)
			$("big_picture").html("Loading...")
			jQuery.ajax({
				type:'GET',
				url:'/events.js',
				dataType: 'script',
				complete: results
				})

$(document).ready(big_picture)
$(document).ready(loading)
$(document).on('page:load', big_picture)
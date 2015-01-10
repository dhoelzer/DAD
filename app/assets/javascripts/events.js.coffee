# Place all the behaviors and hooks related to the matching controller here.
# All this logic will automatically be available in application.js.
# You can use CoffeeScript in this file: http://coffeescript.org/

render_graph ->
	{
		$().ajax({
			type:'GET',
			url:'/events',
			dataType: 'script'
		});
		return false;
	}
	
$(document).ready(render_graph)
$(document).on('page:load', render_graph)

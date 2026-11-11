// System-page gauge bootstrap.
//
// This was systems.js.coffee, and it carried the same `complete: $.ajax()`
// mistake as events.js.coffee -- see the comment there for what that actually
// did. Dropped here too.
//
// Currently inert: the only #system-gauges element is commented out in
// systems/show.html.erb, so setupSystems never fires. Kept rather than deleted
// so uncommenting that block still works.
(function () {
  function drawGauges() {
    jQuery.ajax({
      type: 'GET',
      url: '/systems.js',
      dataType: 'script'
    });
  }

  function setupSystems() {
    if ($("#system-gauges").length) {
      drawGauges();
    }
  }

  $(document).ready(setupSystems);
  $(document).on('page:load', setupSystems);
})();

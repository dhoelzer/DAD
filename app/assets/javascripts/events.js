// Dashboard bootstrap: kick off the first /events.js render and arm the spinner.
//
// This was events.js.coffee. Converted to plain JS so the app's own behaviour is
// readable without a CoffeeScript step; coffee-rails itself has to stay, because
// turbolinks 2.5.4 ships its own turbolinks.js.coffee.
//
// The old CoffeeScript read
//
//     complete: $.ajax()
//
// which *calls* $.ajax() with no options while building the options object, then
// hands the returned jqXHR to `complete`. jQuery's Callbacks.add drops anything
// that is not a function, so the callback never ran; the side effect was a second
// XHR to document.location.href -- jQuery's ajaxSettings.url -- on top of the one
// this function means to make. On the dashboard that meant a full HTML render of
// /events every time the poll fired. Dropped rather than replaced: there was
// never a working callback here to restore.
(function () {
  function bigPicture() {
    jQuery.ajax({
      type: 'GET',
      url: '/events.js',
      dataType: 'script'
    });
  }

  function attachSpinner() {
    if ($("#spinner").length) {
      $("#spinner").hide();
    }
    if ($("#searchload").length) {
      $("*[id*=searchload]").each(function () {
        $(this).click(function () {
          $("#spinner").show();
        });
      });
    }
  }

  function setup() {
    attachSpinner();
    if ($("#big_picture").length) {
      bigPicture();
    }
  }

  $(document).ready(setup);
  $(document).on('page:load', setup);
})();

Events::Application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.cache_classes = true

  # Eager load code on boot. This eager loads most of Rails and
  # your application in memory, allowing both thread web servers
  # and those relying on copy on write to perform better.
  # Rake tasks automatically ignore this option for performance.
  config.eager_load = true

  # Full error reports are disabled and caching is turned on.
  config.consider_all_requests_local       = false
  config.action_controller.perform_caching = true

  # Enable Rack::Cache to put a simple HTTP cache in front of your application
  # Add `rack-cache` to your Gemfile before enabling this.
  # For large-scale production use, consider using a caching reverse proxy like nginx, varnish or squid.
  # config.action_dispatch.rack_cache = true

  # Disable Rails's static asset server (Apache or nginx will already do this).
  config.public_file_server.enabled = false

  # Compress JavaScripts and CSS.
  #
  # Terser, not Uglifier. Uglifier 2.7 wraps UglifyJS 2.x, which predates ES6 and
  # aborts on the first arrow function; Chart.js 4 ships ES2015+, so the bundle
  # cannot be built with it. sprockets 3.7 has no :terser symbol (it only knows
  # :uglifier), and its js_compressor= accepts any object responding to #compress,
  # so the instance is passed directly. Terser is a pure-Ruby wrapper over the
  # terser npm package and needs a JS runtime at precompile time, as Uglifier did.
  config.assets.js_compressor = Terser.new
  # config.assets.css_compressor = :sass

  # Serve only what `rake assets:precompile` wrote; never compile on demand.
  #
  # This line used to be commented out, which left compile at its default of
  # true: sprockets then mounts a /assets route that compiles each bundle on the
  # first request for it -- ~1.8s for application.js on this app -- and caches it
  # under tmp/cache/assets. That made the README's precompile step decorative and
  # turned a broken asset into a runtime 500 instead of a failed deploy. With
  # compile = false a missing asset fails at precompile time, where CI can see it.
  config.assets.compile = false

  # Emit fingerprinted paths (/assets/application-<digest>.js) so Apache serves
  # the files precompile actually wrote, straight out of public/assets.
  #
  # This used to be false, on the reasoning that Rails 4.2 read
  # config.assets.enabled = false as "no asset pipeline" and so emitted
  # undigested paths. That reasoning no longer holds: sprockets-rails 3.x ignores
  # assets.enabled entirely and precompile writes *only* digested filenames.
  # digest = false therefore made the helpers ask for /assets/application.js --
  # a file precompile never produces -- so nothing on disk could serve it and the
  # request could only be satisfied by the runtime compile above. The two settings
  # were coupled; both are corrected here.
  #
  # Verified end to end: after a production precompile, every path the app emits
  # (the layout's stylesheet and script tags, and the url() the compiled CSS
  # resolves for the spinner) exists on disk under public/assets.
  config.assets.digest = true

  # Version of your assets, change this if you want to expire all your assets.
#  config.assets.version = '1.0'

  # Specifies the header that your server uses for sending files.
  # config.action_dispatch.x_sendfile_header = "X-Sendfile" # for apache
  # config.action_dispatch.x_sendfile_header = 'X-Accel-Redirect' # for nginx

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  # config.force_ssl = true

  # Set to :debug to see everything in the log.
  config.log_level = :info

  # Prepend all log lines with the following tags.
  # config.log_tags = [ :subdomain, :uuid ]

  # Use a different logger for distributed setups.
  # config.logger = ActiveSupport::TaggedLogging.new(SyslogLogger.new)

  # Use a different cache store in production.
  # config.cache_store = :mem_cache_store

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.action_controller.asset_host = "http://assets.example.com"

  # Precompile additional assets.
  # application.js, application.css, and all non-JS/CSS in app/assets folder are already added.
  # config.assets.precompile += %w( search.js )

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation can not be found).
  config.i18n.fallbacks = true

  # Send deprecation notices to registered listeners.
  config.active_support.deprecation = :notify

  # Disable automatic flushing of the log to improve performance.
  # config.autoflush_log = false

  # Use default logging formatter so that PID and timestamp are not suppressed.
  config.log_formatter = ::Logger::Formatter.new
end

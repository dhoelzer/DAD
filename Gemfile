source 'https://rubygems.org'

# Rails 7.1 was the last line that runs on Ruby 2.7; that step also moved Ruby to
# 3.3 (RECOMMENDATIONS.md 5.2). This step is 7.1 -> 7.2. Keep this in lockstep
# with .ruby-version, .github/workflows/ci.yml and Dockerfile.dev.
gem 'rails', '~> 7.2.0'

# Transitive dependency of rails-html-sanitizer, capybara and cucumber-rails.
# The 1.15 line was pinned only because it was the last one supporting Ruby 2.7;
# 1.16+ requires Ruby >= 3.0, which this app now satisfies.
gem 'nokogiri', '~> 1.16'

# Ruby 3.3 ships json 3.x as a default gem, and json 3.0 dropped the
# quirks_mode option that ActiveSupport's JSON encoder passes
# (active_support/json/encoding.rb#stringify). Every to_json call then dies with
# "unknown keyword: quirks_mode" -- which takes down all 34 jbuilder views.
# Verified against the actual sources: 7.1.6, 7.2.3 and 8.0.5 all still pass the
# option; only 8.1.4 stopped. So this pin stays through the 7.2 and 8.0 steps and
# can only be dropped at 8.1.
gem 'json', '~> 2.7'

group :production do
  # 0.21 predates Ruby 3. Not exercised by CI (BUNDLE_WITHOUT=production), so the
  # bump is unverified locally; 1.5 is the last 1.x line and builds on Ruby 3.3.
  gem 'pg', '~> 1.5'
end

group :development, :test do
  # The 7.2 sqlite3 adapter accepts >= 1.4 and 2.x. The ceiling keeps the
  # adapter contract this app already relies on; 2.x only becomes mandatory at
  # Rails 8.0, whose adapter requires sqlite3 >= 2.1.
  gem 'sqlite3', '~> 1.7', '< 2'
  # railties 7.1's TestUnit runner calls Minitest::Test.run(reporter, options,
  # suite); minitest 6 narrowed that to (reporter, options) and every test dies
  # with "wrong number of arguments (given 3, expected 1..2)". railties only
  # declares `minitest >= 5.1`, so the 5.x line must be pinned explicitly.
  gem 'minitest', '~> 5.25'
  # There is no spec/ directory and no rspec *example* code, but the cucumber
  # step definitions call rspec-expectations' `expect`, which cucumber-rails only
  # mixes into Cucumber::Rails::World when rspec/rails/matchers is loadable.
  # Removing this gem silently breaks all four cucumber scenarios.
  gem 'rspec-rails', '~> 6.1'
  gem 'cucumber-rails', '~> 2.6', require: false
  gem 'database_cleaner', '~> 1.7'
end

group :development do
  # 7.x understands the Rails 7.1 route/callback DSL; 5.4 predates it and
  # mis-parses the app. Still non-blocking in CI (RECOMMENDATIONS.md 1.2).
  gem 'brakeman', '~> 7.0'
  gem 'bundler-audit', '~> 0.9'
end

# Transitive dependency of actionmailer. The app has no mailers and never
# references Mail directly, so the only reason this line exists is to keep the
# version explicit. It used to pin 2.7.x, but actionmailer >= 7.2.0 requires
# mail >= 2.8.0, so the 2.7 line makes Rails 7.2+ unresolvable. 2.8/2.9 are
# API-compatible for everything actionmailer uses.
gem 'mail', '~> 2.8'

# For JSON requests for the IP Address blocking service.
gem 'httparty', '~> 0.18.0'

# CodeMirror is vendored under vendor/assets (three files added with the Rails 6.1
# step). The codemirror-rails gem capped railties at < 6.0 and has not been
# released since 2016, so it cannot resolve against Rails 6.1. Verified the
# sprockets-built application.js/application.css are byte-identical to the 5.2
# build, so the vendored copies are a drop-in replacement.

# Use SCSS for stylesheets. 5.0.x declares railties >= 5.2.0 with no upper bound
# and still pins sprockets < 4.0, which keeps the existing (sprockets 3.7) asset
# pipeline intact. The 6.x line would drag in sprockets 4 and sassc.
gem 'sass-rails', '~> 5.0.7'

# Use Uglifier as compressor for JavaScript assets. 2.7 is pure Ruby over execjs
# and needs a JS runtime (node) at precompile time, as it always has.
gem 'uglifier', '~> 2.7'

# Use CoffeeScript for .js.coffee assets and views. 4.2.x is required: the 4.0.x
# line caps railties at < 5.0.
gem 'coffee-rails', '~> 4.2.2'

# Use jquery as the JavaScript library. 4.3.x is the oldest line compatible with
# the rails-dom-testing 2.0 that Rails 5.2 pulls in.
gem 'jquery-rails', '~> 4.3.5'

# Turbolinks makes following links in your web application faster.
# Pinned to the 2.x line: the views use `data-no-turbolink`, which Turbolinks 5
# replaced with `data-turbolinks-action`.
gem 'turbolinks', '~> 2.5'

# Build JSON APIs with ease. The 34 .jbuilder views use only json.array!,
# json.extract! and json.url, all unchanged in 2.x.
# 2.7.0's JbuilderTemplate handler takes one argument; Rails 6.1's template
# compiler calls it with two, so every .json.jbuilder view dies with
# "wrong number of arguments (given 2, expected 1)".
gem 'jbuilder', '~> 2.11'

group :doc do
  # bundle exec rake doc:rails generates the API under doc/api.
  # 0.4 pins json ~> 1.7 and rdoc ~> 4.0; json 1.8 has no Ruby 3 support and
  # fails to build its C extension on Ruby 3.3, so the 2.x line is required.
  gem 'sdoc', '~> 2.6', require: false
end

# Password hashing for User#store_password / #check_password.
gem 'bcrypt', '~> 3.1.20'

# Use unicorn as the app server
# gem 'unicorn'

# Use Capistrano for deployment
# gem 'capistrano', group: :development

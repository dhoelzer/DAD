source 'https://rubygems.org'

# Rails 7.1 was the last line that runs on Ruby 2.7; that step also moved Ruby to
# 3.3 (RECOMMENDATIONS.md 5.2). This step is 8.0 -> 8.1, the current stable line.
# Rails 8.1 requires Ruby >= 3.2, so 3.3.8 still works. Keep this in lockstep
# with .ruby-version, .github/workflows/ci.yml and Dockerfile.dev.
gem 'rails', '~> 8.1.0'

# Transitive dependency of rails-html-sanitizer, capybara and cucumber-rails.
# The 1.15 line was pinned only because it was the last one supporting Ruby 2.7;
# 1.16+ requires Ruby >= 3.0, which this app now satisfies.
gem 'nokogiri', '~> 1.16'

# json must stay on the 2.x line. There are TWO independent reasons, and the
# second one is easy to miss:
#
# 1. quirks_mode. json 3.0 dropped the quirks_mode keyword that ActiveSupport's
#    JSON encoder passed (active_support/json/encoding.rb#stringify); every
#    to_json call died with "unknown keyword: quirks_mode", taking down all 34
#    jbuilder views. 7.1.6, 7.2.3 and 8.0.5 all still passed it. This reason is
#    gone at 8.1.4, which calls plain JSON.generate(jsonified).
# 2. create_additions. Sprockets' manifest reader calls
#    JSON.parse(obj, create_additions: false) -- sprockets 3.7.5 line 319, and
#    still present in sprockets 4.2.2. json 3.x removed that keyword too, so
#    booting with an existing public/assets/.sprockets-manifest-*.json raises
#    "unknown keyword: create_additions" from the sprockets-rails railtie, i.e.
#    the app cannot boot at all.
#
# Reason 2 is not fixed by any Rails upgrade; it is a sprockets constraint, and
# it only bites when a manifest file already exists -- which is production, not a
# fresh CI checkout. Verified: json 2.21.2 accepts both keywords, so it satisfies
# sprockets and Rails 8.1 simultaneously. Do not "clean up" this pin to 3.x
# without also moving off sprockets' JSON.parse(create_additions:) manifest.
gem 'json', '~> 2.7'

group :production do
  # 0.21 predates Ruby 3. Not exercised by CI (BUNDLE_WITHOUT=production), so the
  # bump is unverified locally; 1.5 is the last 1.x line and builds on Ruby 3.3.
  gem 'pg', '~> 1.5'
end

group :development, :test do
  # The 8.0 sqlite3 adapter requires sqlite3 >= 2.1 (it calls into the 2.x
  # SQLite3::Statement/Database API), so the < 2 ceiling from the 7.x steps has
  # to go. Precompiled 2.x binaries cover x86_64-linux, so no local toolchain is
  # needed.
  gem 'sqlite3', '~> 2.1'
  # railties' TestUnit runner calls Minitest::Test.run(reporter, options, suite);
  # minitest 6 narrowed that to (reporter, options) and every test dies with
  # "wrong number of arguments (given 3, expected 1..2)". railties only declares
  # `minitest >= 5.1` (8.0 drops it from the runtime deps entirely), so the 5.x
  # line must be pinned explicitly.
  gem 'minitest', '~> 5.25'
  # There is no spec/ directory and no rspec *example* code, but the cucumber
  # step definitions call rspec-expectations' `expect`, which cucumber-rails only
  # mixes into Cucumber::Rails::World when rspec/rails/matchers is loadable.
  # Removing this gem silently breaks all four cucumber scenarios.
  gem 'rspec-rails', '~> 6.1'
  # 2.6.x caps railties at < 8, so it cannot resolve against Rails 8. 3.1.x is
  # the oldest line that supports railties 8 (>= 5.2, < 9) while keeping the
  # cucumber-rails 2.x env.rb API this app's features/support/env.rb uses.
  gem 'cucumber-rails', '~> 3.1', require: false
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

# Removed: httparty ~> 0.18.0. The comment above it read "For JSON requests for
# the IP Address blocking service", but no such code exists in this repo -- no
# HTTParty reference in any .rb/.erb/.yml/.js file, and no IP-blocking/geoip
# code at all. The 0.18.x line carries CVE-2025-68696 (High) and
# CVE-2024-22049, and it was the only High-severity advisory left. If that
# feature is ever built, add a current httparty (0.24.x) then.

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
#
# Raised to 4.6.x for CVE-2020-11023 / CVE-2020-23064 (jQuery core XSS, fixed in
# jQuery 3.5.0). The gem version alone was not enough: jquery-rails ships three
# jQuery lines (jquery.js = 1.12.4, jquery2.js = 2.2.4, jquery3.js = 3.7.0) and
# the manifest's `//= require jquery` selected 1.12.4. application.js now
# requires jquery3, which is what actually clears the advisories. See the
# highcharts-custom.js note: the vendored Highcharts 4.0.4 jQuery adapter had to
# be patched from .bind()/.unbind() (removed in jQuery 3.0) to .on()/.off().
gem 'jquery-rails', '~> 4.6.0'

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

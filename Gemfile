source 'https://rubygems.org'

# Rails 5.2.8.1 is the last release of the 5.2 line. The 4.2 -> 8 upgrade is
# staged (RECOMMENDATIONS.md 5.2); 5.2 is the first step that still runs on Ruby
# 2.7, so the Ruby jump is deferred to the 7.2 step. Keep this in lockstep with
# .github/workflows/ci.yml and Dockerfile.dev.
gem 'rails', '~> 5.2.5'

# Ruby 2.7 ships bigdecimal 2.x, which removed BigDecimal.new. Rails 5.2 no
# longer calls it, but the pin is kept so the resolved graph stays close to what
# CI has always built; drop it together with the Ruby upgrade.
gem 'bigdecimal', '~> 1.4.4'

# Transitive dependency of rails-html-sanitizer, capybara and cucumber-rails.
# 1.15.7 is the last line that supports Ruby 2.7 (1.16+ requires Ruby >= 3.0), so
# it is pinned explicitly to stop a `bundle update` pulling an uninstallable
# version. Raise it together with the Ruby upgrade.
gem 'nokogiri', '~> 1.15.7'

group :production do
  gem 'pg', '~> 0.21.0'
end

group :development, :test do
  gem 'sqlite3', '~> 1.3.13'
  gem 'rspec-rails', '~> 3.9'
  gem 'cucumber-rails', '~> 2.0', require: false
  gem 'database_cleaner', '~> 1.7'
end

group :development do
  gem 'brakeman', '~> 5.4'
  gem 'bundler-audit', '~> 0.9'
end

gem 'mail', '~> 2.7.0'

# For JSON requests for the IP Address blocking service.
gem 'httparty', '~> 0.18.0'

gem 'codemirror-rails', '~> 5.16'

# Use SCSS for stylesheets. 5.0.x is the last line that accepts Rails 5.2 while
# still pinning sprockets < 4.0, which keeps the existing asset pipeline intact.
gem 'sass-rails', '~> 5.0.7'

# Use Uglifier as compressor for JavaScript assets
gem 'uglifier', '~> 2.7'

# Use CoffeeScript for .js.coffee assets and views. 4.2.x is required: the 4.0.x
# line caps railties at < 5.0, so it cannot resolve against Rails 5.2.
gem 'coffee-rails', '~> 4.2.2'

# Use jquery as the JavaScript library. 4.3.x is the oldest line compatible with
# the rails-dom-testing 2.0 that Rails 5.2 pulls in.
gem 'jquery-rails', '~> 4.3.5'

# Turbolinks makes following links in your web application faster.
# Pinned to the 2.x line: the views use `data-no-turbolink`, which Turbolinks 5
# replaced with `data-turbolinks-action`.
gem 'turbolinks', '~> 2.5'

# Build JSON APIs with ease. jbuilder 1.x cannot run on Rails 5 (its activesupport
# bound tops out below 5.1). The 34 .jbuilder views use only json.array!,
# json.extract! and json.url, all unchanged in 2.x, so 2.7 renders them
# identically -- verified by diffing all 22 JSON endpoint responses against the
# 4.2 baseline.
gem 'jbuilder', '~> 2.7.0'

group :doc do
  # bundle exec rake doc:rails generates the API under doc/api.
  gem 'sdoc', '~> 0.4', require: false
end

# Password hashing for User#store_password / #check_password.
gem 'bcrypt', '~> 3.1.20'

# Use unicorn as the app server
# gem 'unicorn'

# Use Capistrano for deployment
# gem 'capistrano', group: :development

source 'https://rubygems.org'

# Rails 4.2.11 is the last release of the 4.2 line and carries the fixes for the
# known Rails 4 CVEs. The previous constraint ('> 4') was unbounded, so a fresh
# `bundle install` resolved Rails 8 against Rails-4-era APIs and failed to boot.
# Keep this in lockstep with .github/workflows/ci.yml and Dockerfile.dev.
gem 'rails', '~> 4.2.11'

# Ruby 2.7 ships bigdecimal 2.x, which removed BigDecimal.new; ActiveSupport 4.2
# calls it during boot. Pinning the 1.4 line keeps Rails 4.2 bootable on Ruby 2.7.
gem 'bigdecimal', '~> 1.4.4'

group :production do
  gem 'pg', '~> 0.21.0'
end

group :development, :test do
  gem 'sqlite3', '~> 1.3.13'
  gem 'rspec-rails', '~> 3.5'
  gem 'cucumber-rails', '~> 1.5.0', require: false
  gem 'database_cleaner', '~> 1.5'
end

group :development do
  gem 'brakeman', '~> 5.4'
  gem 'bundler-audit', '~> 0.9'
end

gem 'mail', '~> 2.7.0'

# For JSON requests for the IP Address blocking service.
gem 'httparty', '~> 0.18.0'

gem 'codemirror-rails', '~> 5.16'

# Use SCSS for stylesheets
gem 'sass-rails', '~> 4.0.0'

# Use Uglifier as compressor for JavaScript assets
gem 'uglifier', '~> 2.7'

# Use CoffeeScript for .js.coffee assets and views
gem 'coffee-rails', '~> 4.0.0'

# Use jquery as the JavaScript library
gem 'jquery-rails', '~> 3.1'

# Turbolinks makes following links in your web application faster.
# Pinned to the 2.x line: the views use `data-no-turbolink`, which Turbolinks 5
# replaced with `data-turbolinks-action`.
gem 'turbolinks', '~> 2.5'

# Build JSON APIs with ease.
gem 'jbuilder', '~> 1.2'

group :doc do
  # bundle exec rake doc:rails generates the API under doc/api.
  gem 'sdoc', '~> 0.4', require: false
end

# Use ActiveModel has_secure_password
# gem 'bcrypt', '~> 3.1.7'

# Use unicorn as the app server
# gem 'unicorn'

# Use Capistrano for deployment
# gem 'capistrano', group: :development

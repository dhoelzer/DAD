# The DAD application image: web, importer, scheduler, and the test suite all run
# from this one image (see docker-compose.yml, which gives each its own container).
# The database is NOT in this image -- it is a separate postgres container.
#
# The base tag is pinned to a patch release: an unpinned `ruby:3` tag silently
# breaks the app on a future minor release. Ruby 3.3 satisfies Rails 8.1 (which
# needs >= 3.2); the app moved off 2.7 because nokogiri/sqlite3 and the json
# default gem no longer support it. Keep this in lockstep with .ruby-version,
# Gemfile, docker-compose.yml and .github/workflows/ci.yml.
FROM ruby:3.3.8

RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
      build-essential \
      libsqlite3-dev \
      libpq-dev \
      perl \
      postgresql-client \
      nodejs && \
    rm -rf /var/lib/apt/lists/*

# nodejs is not optional. Execjs needs a JavaScript runtime, and
# javascript_include_tag in app/views/layouts/application.html.erb goes through
# the sprockets/coffee pipeline, which calls ExecJS. Without a runtime every view
# render raises "Could not find a JavaScript runtime" -- 43 errors in the suite,
# all of them layout renders. CI does not show this because GitHub's
# ubuntu-24.04 runners ship Node; a bare ruby:* image does not.

# postgresql-client is here so `docker compose exec` can run psql against the db
# container for the schema-shape and INVALID-index assertions, and so an operator
# can inspect the database from inside the app container.

# Bundler version is pinned by the "BUNDLED WITH" section of Gemfile.lock.
# RUN is load-bearing here: the file this replaced had a bare `gem install` line,
# which is not a Dockerfile instruction, so the image could never build at all.
# Nothing caught it -- no CI job builds this image.
RUN gem install bundler -v 2.6.7 --no-document

ENV BUNDLE_PATH=/usr/local/bundle

# Deliberately NOT BUNDLE_WITHOUT=production. `pg` sits in the Gemfile's
# :production group, and this image now talks to Postgres -- excluding that group
# leaves the pg gem absent and every database connection fails with
# "LoadError: cannot load such file -- pg". sqlite3 stays too: the SQLite-only
# assertions (query-plan and bytewise-collation tests) still need it.

# /var/DAD, not /app. This is the path production uses -- every systemd unit sets
# WorkingDirectory=/var/DAD -- and syslog.pl hardcodes absolute paths under it
# ($LOGSTAGING="/var/DAD/Logs/LogStaging"). Matching it means the importer's
# relative paths (Dir.chdir('Logs/LogsToProcess'), then '../ProcessedLogs') and
# the collector's absolute ones resolve to the same directories in the container
# as on a provisioned host. Pick any other WORKDIR and the collector silently
# writes into a directory the importer never reads.
WORKDIR /var/DAD

COPY Gemfile Gemfile.lock ./
RUN bundle install --frozen

COPY . .

# The importer and the collector write here, and Rails writes log/. Named volumes
# are mounted over both, so ownership has to be set on the directories
# themselves, not just their current contents.
RUN useradd --create-home --uid 1000 dad && \
    mkdir -p /var/DAD/Logs/LogStaging /var/DAD/Logs/LogsToProcess /var/DAD/Logs/ProcessedLogs && \
    chown -R dad:dad /var/DAD

USER dad

EXPOSE 3000

# Default is the web process; compose overrides per service.
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0"]

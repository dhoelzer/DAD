# Stage 1: build the syslog collector.
#
# A separate stage because the toolchain is ~1 GB and only one 550 KB binary
# comes out of it. The Ruby image never sees cargo.
#
# Pinned to the same minor the CI `collector` job builds with, so the binary in
# the image and the one CI tests are the same.
FROM rust:1.85.1 AS collector

WORKDIR /build

# Manifest first, sources second: cargo's layer cache is keyed on Cargo.toml, so
# editing a .rs file does not re-resolve dependencies. There are no dependencies
# (see syslog_collector/Cargo.toml), which also means no Cargo.lock churn.
#
# tests/ is deliberately not copied: `cargo build --release` compiles only the
# bin target, so including it would bust this layer on every test edit for
# nothing. The CI `collector` job is what runs the tests.
COPY syslog_collector/Cargo.toml ./
COPY syslog_collector/src ./src

# --release because this is the artifact production runs. The dev profile is
# ~10x slower and 4x larger, and there is no reason to ship it.
RUN cargo build --release

# Stage 2: install the gems.
#
# A separate stage because installing them needs a C toolchain and nothing at
# runtime does. build-essential and libpq-dev are required here -- but they are
# ~700 MB of the old single-stage image and are never touched once the gems exist.
#
# The lockfile carries precompiled variants for pg and nokogiri (including
# -musl), but not for bigdecimal or bcrypt, so a compiler is not optional.
# Verified: `bundle install --frozen` on a bare ruby:3.3.8-slim dies with
# "An error occurred while installing bigdecimal".
FROM ruby:3.3.8-slim AS gems

RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
      build-essential \
      libpq-dev && \
    rm -rf /var/lib/apt/lists/*

# Bundler version is pinned by the "BUNDLED WITH" section of Gemfile.lock.
# RUN is load-bearing here: the file this replaced had a bare `gem install` line,
# which is not a Dockerfile instruction, so the image could never build at all.
# Nothing caught it -- no CI job builds this image.
RUN gem install bundler -v 2.6.7 --no-document

ENV BUNDLE_PATH=/usr/local/bundle

# No BUNDLE_WITHOUT at all. `pg` is not in a Gemfile group any more -- Postgres is
# the only engine this app runs -- so there is no group worth excluding, and
# excluding one is exactly how the image used to end up without the driver it
# needs ("LoadError: cannot load such file -- pg").
WORKDIR /var/DAD

COPY Gemfile Gemfile.lock ./
RUN bundle install --frozen

# Stage 3: the runtime image.
#
# -slim, not the bare ruby tag: 143 MB of Debian against 950 MB. Nothing here
# needs anything beyond Debian -- there is no Ubuntu base in this repo, and the
# collector binary from stage 1 is glibc-linked, which Debian provides.
FROM ruby:3.3.8-slim

RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
      nodejs \
      postgresql-client \
      libpq5 && \
    rm -rf /var/lib/apt/lists/*

# libpq5 is the runtime half of libpq-dev and it is not optional: the pg gem's
# C extension links against libpq.so.5, so an image with the gem installed but
# without this library fails at require time, not build time.

# perl is gone. The only thing in the image that needed it was the syslog
# collector, now a Rust binary built in stage 1.

# nodejs is not optional. Execjs needs a JavaScript runtime, and
# javascript_include_tag in app/views/layouts/application.html.erb goes through
# the sprockets/coffee pipeline, which calls ExecJS. Without a runtime every view
# render raises "Could not find a JavaScript runtime" -- 43 errors in the suite,
# all of them layout renders. CI does not show this because GitHub's
# ubuntu-24.04 runners ship Node; a bare ruby:* image does not.

# postgresql-client is here so `docker compose exec` can run psql against the db
# container for the schema-shape and INVALID-index assertions, and so an operator
# can inspect the database from inside the app container.

ENV BUNDLE_PATH=/usr/local/bundle

# Bundler again. `gem install bundler` in stage 2 wrote it to Ruby's default gem
# directory, not to $BUNDLE_PATH, so COPY --from=gems does not carry it. Ruby
# 3.3.8 ships a newer bundler than Gemfile.lock's "BUNDLED WITH 2.6.7", and
# `bundle install --frozen` in stage 2 would then be a different bundler from the
# one running `bundle exec` here.
RUN gem install bundler -v 2.6.7 --no-document

# /var/DAD, not /app. This is the path production uses -- every systemd unit sets
# WorkingDirectory=/var/DAD -- and the collector hardcodes absolute paths under it
# (DEFAULT_STAGING="/var/DAD/Logs/LogStaging"). Matching it means the importer's
# relative paths (Dir.chdir('Logs/LogsToProcess'), then '../ProcessedLogs') and
# the collector's absolute ones resolve to the same directories in the container
# as the systemd units expect. Pick any other WORKDIR and the collector silently
# writes into a directory the importer never reads.
WORKDIR /var/DAD

# The gem layer, already compiled. This is the whole point of stage 2: the
# toolchain that produced it stays behind there.
COPY --from=gems /usr/local/bundle /usr/local/bundle

# Gemfile and Gemfile.lock again, separately from `COPY . .`, so `bundle exec`
# can find them and so the cached gem layer is not busted by an app edit.
COPY Gemfile Gemfile.lock ./
COPY . .

# The collector binary, not the crate. Nothing in the runtime image needs cargo,
# rustc, or the build cache.
COPY --from=collector /build/target/release/syslog_collector /usr/local/bin/syslog_collector

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

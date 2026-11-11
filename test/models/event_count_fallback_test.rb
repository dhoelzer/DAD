require 'test_helper'
require_relative '../support/scratch_database'

# Event.approximate_count reads pg_stat_user_tables and sums the rows of every
# table named events_p*. That view and that naming are both Postgres-specific,
# and the sum comes back NULL when events is not partitioned -- which happens on
# a real install, not just in a test: one prepared with plain `db:migrate` loads
# the committed db/schema.rb dump, which cannot express PARTITION BY.
#
# The fallback to an exact COUNT(*) is therefore live code on Postgres. If the
# nil guard were removed as "dead SQLite support", the dashboard would report 0
# events on such an install rather than failing loudly.
#
# This needs a subprocess: the test database is deliberately partitioned (built by
# db:migrate_from_scratch), so the only way to get an unpartitioned events table on
# Postgres is a scratch database loaded from db/schema.rb.
class EventCountFallbackTest < ActiveSupport::TestCase
  RUBY = RbConfig.ruby

  BOOT = "load 'db/schema.rb'; EventIngestor.resetCaches; "

  def setup
    @db = ScratchDatabase.new('count_fallback')
  end

  def teardown
    @db&.drop
  end

  test 'approximate_count falls back to an exact count on an unpartitioned schema' do
    # Non-interpolating heredoc: the #{...} below belongs to the subprocess.
    body = BOOT + <<~'RUBY'
      3.times { |i| EventIngestor.storeEvent("10.0.0.#{i} Jun 1 00:00:0#{i} host svc[1]: fallback probe #{i}") }
      EventIngestor.performPendingInserts
      EventIngestor.flush_and_wait
      partitioned = ActiveRecord::Base.connection
        .select_all("select relkind from pg_class where relname = 'events'")
        .first['relkind']
      puts "RELKIND=#{partitioned}"
      puts "APPROX=#{Event.approximate_count}"
      puts "EXACT=#{Event.count}"
    RUBY

    out, status = run_development(body)
    assert_equal 0, status, "subprocess failed:\n#{out}"

    # Guards the premise: if the scratch schema ever became partitioned, this test
    # would be asserting the estimate path instead and would pass for the wrong
    # reason.
    assert_equal 'r', out[/RELKIND=(\S+)/, 1],
      'db/schema.rb must load events as an ordinary (unpartitioned) table here'

    approx = out[/APPROX=(\S+)/, 1].to_i
    exact = out[/EXACT=(\S+)/, 1].to_i
    assert_equal 3, exact, "expected 3 stored events, got #{exact}"
    assert_equal exact, approx,
      'on an unpartitioned schema the sum over events_p* is NULL, so the exact ' \
      'COUNT(*) fallback must be used rather than reporting 0'
  end

  private

  def run_development(body)
    out = IO.popen(
      { 'RAILS_ENV' => 'development',
        'DATABASE_URL' => @db.url,
        'SECRET_KEY_BASE' => 'x' * 32 },
      [RUBY, '-e', "require './config/environment'; #{body}"],
      err: %i[child out], &:read
    )
    [out, $?.exitstatus]
  end
end

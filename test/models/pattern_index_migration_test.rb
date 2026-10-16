require 'test_helper'
require_relative '../../db/migrate/20261016000002_add_pattern_index_to_words'

# A CONCURRENTLY index build that fails does not roll back: Postgres keeps the
# half-built index as INVALID, and it still occupies its name. index_exists? and
# index_name_exists? both report it as healthy, because their query does not
# filter pg_index.indisvalid. Re-running the migration then dies on
# `relation ... already exists`, which wedges `rake db:migrate` -- and with it
# provision.sh, since the deploy re-runs the same migration.
#
# AddPatternIndexToWords drops such a husk before rebuilding. These tests cover
# the detection that makes that possible, so the guard cannot be "simplified"
# back into index_exists? later.
class PatternIndexMigrationTest < ActiveSupport::TestCase
  # DDL under test: CONCURRENTLY cannot run inside a transaction, and
  # transactional fixtures would wrap every test in one.
  self.use_transactional_tests = false

  TABLE = 'husk_probe'.freeze
  HUSK = 'husk_probe_pattern_idx'.freeze

  setup do
    skip 'the INVALID-index guard is Postgres-specific' unless
      Event.connection.adapter_name == 'PostgreSQL'
    @conn = Event.connection
    @conn.execute("create table #{TABLE} (id serial primary key, text varchar(255))")
  end

  teardown do
    @conn&.execute("drop table if exists #{TABLE}")
  end

  # A unique index over duplicate rows fails to build, which is exactly what
  # leaves an INVALID husk holding the name.
  def plant_invalid_index(name)
    @conn.execute("insert into #{TABLE}(text) values ('dup'),('dup')")
    @conn.execute("create unique index concurrently #{name} on #{TABLE}(text)")
  rescue ActiveRecord::StatementInvalid
    nil
  end

  def valid?(name)
    @conn.select_value(
      'select i.indisvalid from pg_class c join pg_index i on i.indexrelid = c.oid ' \
      "where c.relname = #{@conn.quote(name)}")
  end

  test 'a failed CONCURRENTLY build leaves an INVALID index holding the name' do
    plant_invalid_index(HUSK)
    assert_equal false, valid?(HUSK), 'precondition: the husk must exist and be INVALID'
    # The trap this migration works around: Rails reads the husk as healthy.
    assert @conn.index_name_exists?(TABLE, HUSK),
      'index_name_exists? cannot distinguish a husk from a usable index'
  end

  test 'the migration detects an INVALID index it owns' do
    plant_invalid_index(HUSK)
    assert_equal HUSK, AddPatternIndexToWords.new.invalid_index_named(HUSK)
  end

  test 'the migration leaves a valid index alone' do
    @conn.execute("create index #{HUSK} on #{TABLE}(text)")
    assert_equal true, valid?(HUSK)
    assert_nil AddPatternIndexToWords.new.invalid_index_named(HUSK),
      'a usable index must never be dropped by the guard'
  end

  test 'the migration tolerates an index that does not exist at all' do
    assert_nil AddPatternIndexToWords.new.invalid_index_named('no_such_index_anywhere')
  end
end

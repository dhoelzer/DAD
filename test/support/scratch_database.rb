require 'erb'
require 'pg'
require 'securerandom'

# A throwaway Postgres database for the tests that run the importer or ingestor
# in a subprocess and then assert on what that subprocess wrote.
#
# They cannot share the test database: transactional fixtures hold an open
# transaction around each test, so the subprocess's committed writes are invisible
# to the parent and the parent's uncommitted fixture rows are invisible to the
# child. Each such test gets its own empty database that both processes reach
# through the same server.
#
# CREATE DATABASE cannot run inside a transaction block, which is why this opens
# its own PG connection rather than going through ActiveRecord::Base.
#
# The subprocess builds the tables itself from db/schema.rb (see each test's BOOT
# string) rather than replaying db/migrate: these tests need the tables, and none
# of them exercise partitioning. schema.rb is that portable description, and it
# loads on Postgres as-is.
class ScratchDatabase
  attr_reader :name, :url

  def initialize(prefix)
    cfg = ActiveRecord::Base.connection_db_config.configuration_hash
    raise 'ScratchDatabase requires a Postgres test database' unless cfg[:adapter] == 'postgresql'

    @name = "#{prefix}_#{Process.pid}_#{SecureRandom.hex(6)}"
    @host = cfg[:host] || 'localhost'
    @port = cfg[:port] || 5432
    @user = cfg[:username]
    @password = cfg[:password]
    @maintenance_db = cfg[:database]
    @url = dsn(@name)

    connect(@maintenance_db) { |conn| conn.exec(%(CREATE DATABASE "#{@name}")) }
  end

  # Reads the scratch database from the parent process, after the subprocess that
  # wrote it has exited. Returns each row as an array of strings.
  #
  # Connects to the scratch database, not the maintenance one: the maintenance
  # database is the test database, which holds fixtures and none of what the
  # subprocess wrote.
  def query(sql)
    connect(@name) { |conn| conn.exec(sql).map { |row| row.values } }
  end

  def drop
    connect(@maintenance_db) { |conn| conn.exec(%(DROP DATABASE IF EXISTS "#{@name}")) }
  end

  private

  def dsn(database)
    # Credentials are URL-encoded: a password containing @ or / would otherwise
    # misparse. URI::Generic#to_s drops userinfo, so the authority is built here.
    user = ERB::Util.url_encode(@user.to_s)
    password = ERB::Util.url_encode(@password.to_s)
    "postgres://#{user}:#{password}@#{@host}:#{@port}/#{database}"
  end

  # One connection per call, so nothing here can hold a transaction open across
  # the DDL that Postgres refuses to run inside one.
  def connect(database)
    conn = PG.connect(dsn(database))
    begin
      yield conn
    ensure
      conn.close
    end
  end
end

require 'test_helper'

# Index actions loaded an entire table with Model.all and rendered every row.
# sessions and statistics grow without bound -- statistics is an append-only
# series written by the ingestion pipeline -- so those admin screens eventually
# stop rendering at all.
class IndexPaginationTest < ActionController::TestCase
  tests SessionsController

  PAGE_SIZE = 25

  setup do
    @request.env['HTTPS'] = 'on'
    right = Right.create!(name: 'Admin', description: 'admin')
    role = Role.create!(name: "Adm#{SecureRandom.hex(6)}", description: 'a')
    role.rights << right
    @admin = User.create!(username: "pg#{SecureRandom.hex(6)}", attempts: 0)
    @admin.store_password('secretsauce'); @admin.save!; @admin.roles << role
    Session.delete_all
    s = Session.create!(user: @admin, expiry: Time.now + 1.hour,
                        session_hash: SecureRandom.hex(16))
    cookies[:sessionID] = s.session_hash
  end

  def make_sessions(n)
    n.times { |i| Session.create!(user: @admin, expiry: Time.now + 3600, session_hash: format('%064x', i)) }
  end

  # Asserted through rendered HTML rather than controller internals: assigns is
  # not available without rails-controller-testing, and the row count the
  # operator actually sees is the thing that matters.
  def rendered_rows
    response.body.scan(%r{<a[^>]*href="/sessions/\d+"[^>]*>Show</a>}).size
  end

  test 'the sessions index renders at most one page' do
    make_sessions(60)
    get :index
    assert_response :success
    assert_operator rendered_rows, :<=, PAGE_SIZE,
      'a page must be bounded regardless of table size'
  end

  test 'page two is reachable and does not repeat page one' do
    make_sessions(60)
    get :index, params: { page: 1 }
    first = response.body.scan(%r{<a[^>]*href="(/sessions/\d+)"[^>]*>Show</a>}).flatten
    get :index, params: { page: 2 }
    second = response.body.scan(%r{<a[^>]*href="(/sessions/\d+)"[^>]*>Show</a>}).flatten
    refute_empty second, 'page 2 must exist once there are more rows than one page'
    assert_empty first & second, 'pages must not overlap'
  end

  # A page param past the end used to offset beyond the last row: the screen
  # rendered an empty list and still offered Prev, so the operator saw nothing
  # and had no way back into the data from that link's label.
  test 'a page past the last one shows the last page, not an empty list' do
    make_sessions(60)
    get :index, params: { page: 999 }
    assert_response :success
    assert_operator rendered_rows, :>, 0, 'an out-of-range page must still show rows'
    assert_match(/Page 3 of 3/, response.body)
  end

  test 'a page link is offered when there is more than one page' do
    make_sessions(60)
    get :index
    assert_match(/page/i, response.body, 'the operator needs to know how to reach the rest')
  end
end

class StatisticsPaginationTest < ActionController::TestCase
  tests StatisticsController
  PAGE_SIZE = 25

  setup do
    @request.env['HTTPS'] = 'on'
    right = Right.create!(name: 'Admin', description: 'admin')
    role = Role.create!(name: "Adm#{SecureRandom.hex(6)}", description: 'a')
    role.rights << right
    @admin = User.create!(username: "sp#{SecureRandom.hex(6)}", attempts: 0)
    @admin.store_password('secretsauce'); @admin.save!; @admin.roles << role
    Session.delete_all
    s = Session.create!(user: @admin, expiry: Time.now + 1.hour,
                        session_hash: SecureRandom.hex(16))
    cookies[:sessionID] = s.session_hash
  end

  test 'the statistics index renders at most one page' do
    rows = (1..60).map { |i| { type_id: 1, stat: i, timestamp: Time.now } }
    Statistic.insert_all(rows)
    get :index
    assert_response :success
    count = response.body.scan(%r{<a[^>]*href="/statistics/\d+"[^>]*>Show</a>}).size
    assert_operator count, :<=, PAGE_SIZE
  end
end

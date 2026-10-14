require 'test_helper'

# End-to-end checks on the single ApplicationController#authorized? gate. These
# cover the behaviour the per-controller overrides used to implement, plus the
# holes they left.
class AuthorizationEnforcementTest < ActionDispatch::IntegrationTest
  def make_user(right_names)
    role = Role.create!(name: "R#{Time.now.to_i}#{rand(99_999)}", description: "r")
    right_names.each do |n|
      r = Right.where(:name => n).first || Right.create!(name: n, description: n)
      role.rights << r
    end
    u = User.create!(username: "u#{Time.now.to_i}#{rand(99_999)}", attempts: 0)
    u.store_password("secretsauce")
    u.roles << role
    token = SecureRandom.hex(16)
    Session.create!(user: u, expiry: Time.now + 1.hour, session_hash: token)
    cookies[:sessionID] = token
    u
  end

  test "the logon page is reachable with no session" do
    get "https://www.example.com/users/logon"
    assert_response :success
  end

  test "an anonymous user is sent to logon" do
    get "https://www.example.com/events"
    assert_response :redirect
    assert_redirected_to logon_users_path
  end

  test "a Viewer can read events but not administer accounts" do
    make_user(["Viewer"])
    get "https://www.example.com/events"
    assert_response :success
    get "https://www.example.com/users"
    assert_response :redirect
    assert_equal "You lack the appropriate rights", flash[:notice]
  end

  # alerts accepts Viewer *or* Commentator; the OR has to survive the move to a
  # single map.
  test "a Commentator can reach the alert queue" do
    make_user(["Commentator"])
    get "https://www.example.com/alerts"
    assert_response :success
  end

  test "a user with no relevant right cannot reach the alert queue" do
    make_user(["Detective"])
    get "https://www.example.com/alerts"
    assert_response :redirect
    assert_equal "You lack the appropriate rights", flash[:notice]
  end

  test "an Admin can reach account administration" do
    make_user(["Admin"])
    get "https://www.example.com/users"
    assert_response :success
  end

  # The inherited gate let any logged-in user rewrite the live dashboard's
  # page size, which is stored in the user_id 0 Preference row.
  test "a non-admin cannot change preferences" do
    make_user(["Viewer"])
    pref = Preference.create!(user_id: 0, liveEventsDisplayed: 10)
    put "https://www.example.com/preferences/#{pref.id}",
        params: { :preference => { :user_id => 0, :liveEventsDisplayed => 999 } }
    assert_response :redirect
    assert_equal 10, Preference.find(pref.id).liveEventsDisplayed,
                 "a Viewer changed the dashboard page size"
  end

  test "an admin can change preferences" do
    make_user(["Admin"])
    pref = Preference.create!(user_id: 0, liveEventsDisplayed: 10)
    put "https://www.example.com/preferences/#{pref.id}",
        params: { :preference => { :user_id => 0, :liveEventsDisplayed => 25 } }
    assert_response :redirect
    assert_equal 25, Preference.find(pref.id).liveEventsDisplayed
  end

  # SessionsController#authorized? was defined twice and the surviving copy
  # redirected to /homes, which is not a route.
  test "a non-admin hitting /sessions is sent to logon, not to a dead path" do
    make_user(["Viewer"])
    get "https://www.example.com/sessions"
    assert_response :redirect
    assert_redirected_to logon_users_path
  end

  test "a Viewer cannot open the new-search form" do
    make_user(["Viewer"])
    get "https://www.example.com/searches/new"
    assert_response :redirect
    assert_equal "You lack the appropriate rights", flash[:notice]
  end

  test "a Detective can open the new-search form" do
    make_user(["Detective"])
    get "https://www.example.com/searches/new"
    assert_response :success
  end

  # /users/authorized matches GET /users/:id, so it reaches #show rather than
  # running the filter as an action. Before the fix #authorized? was a public
  # method and therefore a candidate action on every controller.
  test "authorized? is not dispatched as an action" do
    make_user(["Admin"])
    assert_raises(ActiveRecord::RecordNotFound) do
      get "https://www.example.com/users/authorized"
    end
  end
end

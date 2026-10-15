require 'test_helper'

# The alert queue is how operators see findings; acknowledgement is how they
# dismiss them. These actions had no request-level coverage, so neither the
# state transition nor the index filter that hides closed alerts was pinned.
class AlertAcknowledgeTest < ActionController::TestCase
  tests AlertsController

  setup do
    @request.env['HTTPS'] = 'on'
    right = Right.create!(name: 'Viewer', description: 'view')
    role = Role.create!(name: "Viewers#{SecureRandom.hex(6)}", description: 'v')
    role.rights << right
    user = User.create!(username: "viewer#{SecureRandom.hex(6)}", attempts: 0)
    user.store_password('secretsauce')
    user.roles << role
    cookies[:sessionID] = Session.create!(user: user, expiry: Time.now + 1.hour,
                                          session_hash: SecureRandom.hex(16)).session_hash

    @system = System.create!(address: "ack#{SecureRandom.hex(6)}.example.com",
                             name: "ack#{SecureRandom.hex(6)}")
  end

  attr_reader :system

  # Unique description/short_description per call: the index renders both, so a
  # shared constant would make refute_includes pass or fail for the wrong reason.
  def open_alert(criticality: 3, closed: false)
    tag = SecureRandom.hex(6)
    Alert.create!(system: system, criticality: criticality, generated: Time.now,
                  closed: closed, description: "desc-#{tag}",
                  short_description: "short-#{tag}")
  end

  def test_acknowledge_closes_the_alert
    alert = open_alert

    post :acknowledge, params: { id: alert.id }

    assert alert.reload.closed, 'acknowledge must set closed = true'
  end

  def test_acknowledge_html_redirects_to_the_queue
    alert = open_alert

    post :acknowledge, params: { id: alert.id }

    assert_response :redirect
    assert_redirected_to alerts_url
  end

  # The queue link is remote: true, so the JS branch is the one the UI uses.
  def test_acknowledge_js_rerenders_the_queue
    alert = open_alert

    post :acknowledge, params: { id: alert.id }, xhr: true

    assert_response :success
    assert_equal 'text/javascript', response.media_type
    assert_includes response.body, '#alerts_table'
    assert alert.reload.closed
  end

  # Only open alerts are listed; if acknowledge closed the alert but the filter
  # regressed, closed alerts would keep resurfacing in the queue.
  def test_index_excludes_closed_alerts
    open = open_alert
    closed = open_alert(closed: true)

    get :index

    assert_response :success
    assert_includes response.body, open.short_description
    refute_includes response.body, closed.short_description,
                    'a closed alert must not appear in the open queue'
  end

  def test_ackall_closes_every_open_alert
    a = open_alert
    b = open_alert(criticality: 5)
    already = open_alert(closed: true)

    post :ackall, xhr: true

    assert_response :success
    assert a.reload.closed
    assert b.reload.closed
    assert already.reload.closed
    assert_equal 0, Alert.where(closed: false).count
  end

  # The UI posts with remote:true, so the JS path is what it uses. A plain HTML
  # POST reaches a respond_to block with no html branch and raises UnknownFormat
  # (406 through the real middleware; it propagates in a controller test).
  def test_ackall_only_responds_to_js
    open_alert

    assert_raises(ActionController::UnknownFormat) { post :ackall }
  end

  def test_acknowledge_leaves_other_alerts_open
    target = open_alert
    other = open_alert

    post :acknowledge, params: { id: target.id }

    assert target.reload.closed
    refute other.reload.closed, 'acknowledging one alert must not close others'
  end

  # alerts are gated on Viewer/Commentator; a user with neither must not be able
  # to dismiss the queue.
  # The queue and the alert page must actually render POST forms, otherwise the
  # UI would be pointing at routes that 404.
  def test_index_renders_a_post_form_for_ackall
    open_alert

    get :index

    assert_response :success
    assert_select 'form[action=?][method=?]', ackall_alerts_path, 'post'
  end

  def test_queue_renders_a_post_form_per_alert
    alert = open_alert

    get :index

    assert_select 'form[action=?][method=?]', acknowledge_alert_path(alert), 'post'
  end

  def test_show_renders_a_post_form_for_acknowledge
    alert = open_alert

    get :show, params: { id: alert.id }

    assert_select 'form[action=?][method=?]', acknowledge_alert_path(alert), 'post'
  end

  def test_a_user_without_the_viewer_right_cannot_acknowledge
    right = Right.create!(name: "Nope#{SecureRandom.hex(6)}", description: 'n')
    role = Role.create!(name: "Nope#{SecureRandom.hex(6)}", description: 'n')
    role.rights << right
    outsider = User.create!(username: "outsider#{SecureRandom.hex(6)}", attempts: 0)
    outsider.store_password('secretsauce')
    outsider.roles << role
    cookies[:sessionID] = Session.create!(user: outsider, expiry: Time.now + 1.hour,
                                          session_hash: SecureRandom.hex(16)).session_hash

    alert = open_alert
    post :acknowledge, params: { id: alert.id }

    assert_response :redirect
    refute alert.reload.closed, 'an unauthorised user must not close an alert'
  end
end

# End-to-end guard on the HTTP verb. These are integration tests rather than
# assert_routing calls because the point is observable behaviour: a GET must not
# close an alert. assert_routing reports a miss through Minitest::Assertion,
# which is not a StandardError, so it cannot be wrapped in assert_raises.
#
# The reason these actions are POST: protect_from_forgery only verifies non-GET
# verbs, so a state-changing GET is CSRF-immune -- an <img src> tag or a browser
# link prefetch would close alerts. A revert to `get :acknowledge` fails here.
class AlertAcknowledgeRoutingTest < ActionDispatch::IntegrationTest
  def sign_in_viewer
    right = Right.where(name: 'Viewer').first || Right.create!(name: 'Viewer', description: 'v')
    role = Role.create!(name: "R#{SecureRandom.hex(6)}", description: 'r')
    role.rights << right
    user = User.create!(username: "v#{SecureRandom.hex(6)}", attempts: 0)
    user.store_password('secretsauce')
    user.roles << role
    cookies[:sessionID] = SecureRandom.hex(16)
    Session.create!(user: user, expiry: Time.now + 1.hour, session_hash: cookies[:sessionID])
    user
  end

  def open_alert
    system = System.create!(address: "r#{SecureRandom.hex(6)}.example.com", name: 'r')
    Alert.create!(system: system, criticality: 3, generated: Time.now, closed: false,
                  description: 'd', short_description: 's')
  end

  # show_exceptions = :none in config/environments/test.rb, so an unroutable
  # request raises rather than rendering 404. Both assertions below are the
  # production 404 path; what matters is that neither reaches the action.
  test 'GET /alerts/:id/acknowledge is not routable and closes nothing' do
    sign_in_viewer
    alert = open_alert

    assert_raises(ActionController::RoutingError) do
      get "https://www.example.com/alerts/#{alert.id}/acknowledge"
    end
    refute alert.reload.closed, 'a GET must not acknowledge an alert'
  end

  # /alerts/ackall no longer matches a collection route; it falls through to
  # alerts#show with id="ackall", which cannot find a record. 404 either way --
  # the point is that ackall is not executed.
  test 'GET /alerts/ackall is not routable and closes nothing' do
    sign_in_viewer
    alert = open_alert

    assert_raises(ActiveRecord::RecordNotFound) do
      get 'https://www.example.com/alerts/ackall'
    end
    refute alert.reload.closed, 'a GET must not acknowledge alerts'
  end

  # The payoff of the verb change, checked with forgery protection actually
  # enabled (config/environments/test.rb turns it off globally). A POST without
  # a valid token is rejected; as a GET this request was never inspected at all,
  # because protect_from_forgery only covers non-GET verbs.
  test 'a cross-site POST without a CSRF token is rejected' do
    sign_in_viewer
    alert = open_alert
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    begin
      assert_raises(ActionController::InvalidAuthenticityToken) do
        post "https://www.example.com/alerts/#{alert.id}/acknowledge"
      end
    ensure
      ActionController::Base.allow_forgery_protection = previous
    end
    refute alert.reload.closed, 'a tokenless POST must not acknowledge an alert'
  end

  test 'POST /alerts/:id/acknowledge closes the alert' do
    sign_in_viewer
    alert = open_alert

    post "https://www.example.com/alerts/#{alert.id}/acknowledge"

    assert alert.reload.closed
  end
end

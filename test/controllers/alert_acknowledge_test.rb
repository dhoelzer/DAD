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

    get :acknowledge, params: { id: alert.id }

    assert alert.reload.closed, 'acknowledge must set closed = true'
  end

  def test_acknowledge_html_redirects_to_the_queue
    alert = open_alert

    get :acknowledge, params: { id: alert.id }

    assert_response :redirect
    assert_redirected_to alerts_url
  end

  # The queue link is remote: true, so the JS branch is the one the UI uses.
  def test_acknowledge_js_rerenders_the_queue
    alert = open_alert

    get :acknowledge, params: { id: alert.id }, xhr: true

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

    get :ackall, xhr: true

    assert_response :success
    assert a.reload.closed
    assert b.reload.closed
    assert already.reload.closed
    assert_equal 0, Alert.where(closed: false).count
  end

  # The link is remote:true, so the JS path is what the UI uses. A plain HTML
  # GET reaches a respond_to block with no html branch and raises
  # UnknownFormat -- 406 through the real exception middleware, but it propagates
  # in a controller test. Pinned so the JS-only contract is explicit.
  def test_ackall_only_responds_to_js
    open_alert

    assert_raises(ActionController::UnknownFormat) { get :ackall }
  end

  def test_acknowledge_leaves_other_alerts_open
    target = open_alert
    other = open_alert

    get :acknowledge, params: { id: target.id }

    assert target.reload.closed
    refute other.reload.closed, 'acknowledging one alert must not close others'
  end

  # alerts are gated on Viewer/Commentator; a user with neither must not be able
  # to dismiss the queue.
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
    get :acknowledge, params: { id: alert.id }

    assert_response :redirect
    refute alert.reload.closed, 'an unauthorised user must not close an alert'
  end
end

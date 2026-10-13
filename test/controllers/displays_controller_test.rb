require 'test_helper'

# The Displays screen used to accept arbitrary Ruby, evaluated by Event#parsed
# while rendering every event row. It now takes a declarative spec.
class DisplaysControllerTest < ActionController::TestCase
  tests DisplaysController

  setup do
    @request.env['HTTPS'] = 'on'
    right = Right.create!(name: "Detective", description: "detective")
    role = Role.create!(name: "Detectives#{Time.now.to_i}", description: "detectives")
    role.rights << right
    @user = User.create!(username: "det#{Time.now.to_i}", attempts: 0)
    @user.store_password("secretsauce")
    @user.roles << role
    @session_hash = SecureRandom.hex(16)
    Session.create!(user: @user, expiry: Time.now + 1.hour, session_hash: @session_hash)
    cookies[:sessionID] = @session_hash
  end

  test "the form documents directives instead of offering a Ruby editor" do
    get :new
    assert_response :success
    assert_select "textarea#display_display_script"
    assert_match(/fields 1,2,5/, response.body)
    refute_match(/CodeMirror/, response.body)
  end

  test "creating a display with a valid spec succeeds" do
    assert_difference "Display.count" do
      post :create, display: { name: "ssh", key: "sshd", display_script: "fields 4,5" }
    end
    assert_equal "fields 4,5", Display.last.display_script
  end

  test "creating a display with Ruby is rejected and nothing is executed" do
    marker = Rails.root.join("tmp_pwned_display")
    File.delete(marker) if File.exist?(marker)
    assert_no_difference "Display.count" do
      post :create, display: { name: "evil", key: "x", display_script: "File.write('#{marker}','ran')" }
    end
    refute File.exist?(marker)
  end

  test "Event#parsed interprets the spec rather than evaluating it" do
    Display.create!(name: "ssh", key: "sshd", display_script: "fields 4,5\njoin ,")
    event = Event.new(hunks: "Apr 12 10:22:01 host sshd[1234]: Failed password")
    assert_equal "host,sshd[1234]:", event.parsed
  end
end

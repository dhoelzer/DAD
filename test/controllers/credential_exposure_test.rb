require 'test_helper'

# The users CRUD screens are Admin-gated, but an admin's browser is not a
# trusted place to put credential material: it lands in page HTML, browser
# history, proxy and CDN logs, and any XSS on the page can read it. These
# render the real pages and assert no bcrypt hash is ever emitted.
#
# The edit form is covered for a second reason: as a text_field it prefilled
# the stored hash, and submitting the form without touching the password field
# re-hashed it (bcrypt of the old hash), locking the account out.
class CredentialExposureTest < ActionDispatch::IntegrationTest
  setup do
    admin_right = Right.create!(name: 'Admin', description: 'admin')
    role = Role.create!(name: "Admins#{SecureRandom.hex(6)}", description: 'admins')
    role.rights << admin_right
    admin = User.create!(username: "admin#{SecureRandom.hex(6)}", attempts: 0)
    admin.store_password('secretsauce')
    admin.roles << role
    cookies[:sessionID] = Session.create!(user: admin, expiry: Time.now + 1.hour,
                                          session_hash: SecureRandom.hex(16)).session_hash

    @victim = User.create!(username: "victim#{SecureRandom.hex(6)}", attempts: 0)
    @victim.store_password('victim-pw')
    @victim.save!
    @hash = @victim.password
  end

  # Sanity check on the fixture: a bcrypt hash is what we are looking for.
  def test_fixture_stores_a_bcrypt_hash
    assert_match(/\A\$2[aby]\$\d{2}\$/, @hash)
  end

  def test_index_does_not_emit_password_hashes
    get 'https://www.example.com/users'
    assert_response :success
    refute_includes response.body, @hash, 'index must not render the stored hash'
    refute_match(/Password/i, response.body,
                 'index must not advertise a Password column')
  end

  def test_show_does_not_emit_the_password_hash
    get "https://www.example.com/users/#{@victim.id}"
    assert_response :success
    refute_includes response.body, @hash
  end

  def test_edit_does_not_prefill_the_password_hash
    get "https://www.example.com/users/#{@victim.id}/edit"
    assert_response :success
    refute_includes response.body, @hash

    field = response.body[/<input[^>]*name="user\[password\]"[^>]*>/].to_s
    refute_empty field, 'the edit form must still render a password field'
    refute_match(/value="/, field,
                 'the password field must not carry a value attribute')
    assert_match(/type="password"/, field,
                 'the field must be masked, not a visible text input')
  end

  # The functional half of the same defect: a browser submits whatever the form
  # rendered, so a prefilled hash silently becomes bcrypt(old hash).
  def test_resubmitting_the_edit_form_keeps_the_password_working
    get "https://www.example.com/users/#{@victim.id}/edit"
    prefilled = response.body[/<input[^>]*name="user\[password\]"[^>]*>/]
                           .to_s[/value="([^"]*)"/, 1]
    assert_nil prefilled, 'nothing should be prefilled to submit back'

    patch "https://www.example.com/users/#{@victim.id}",
          params: { user: { username: @victim.username, first: 'Ada', password: '' } }
    assert_response :redirect

    @victim.reload
    assert @victim.check_password('victim-pw'),
           'an untouched password field must not change the password'
    refute @victim.check_password(@hash),
           'the stored hash must never become the new password'
  end

  # The .json endpoints already whitelist attributes; pin that so a future
  # `json.extract! user, ... :password` cannot regress silently.
  def test_json_endpoints_do_not_emit_passwords
    get 'https://www.example.com/users.json'
    assert_response :success
    refute_includes response.body, @hash
    refute_includes response.body, 'password'

    get "https://www.example.com/users/#{@victim.id}.json"
    assert_response :success
    refute_includes response.body, @hash
    refute_includes response.body, 'password'
  end
end

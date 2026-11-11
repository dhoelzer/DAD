require 'system_helper'

# The logon flow end to end: the form, the POST, the session cookie, and the
# gatekeeper that reads it. The controller tests assert the policy; these assert
# the form actually posts to a route that exists and that the resulting page is
# the one the operator expects.
class AuthenticationTest < SystemTest
  setup do
    @right = Right.create!(name: 'Viewer', description: 'can view events')
    @role = Role.create!(name: 'Viewers', description: 'viewers')
    @role.rights << @right
    @user = User.create!(username: 'syslogin', attempts: 0)
    @user.store_password('secretsauce')
    @user.roles << @role
    @user.save
  end

  test 'the logon form posts to do_logon and signs the user in' do
    visit '/users/logon'

    assert_selector 'input[type=password][name="user[password]"]'
    assert_selector 'input[type=text][name="user[username]"]'

    fill_in 'user[username]', with: 'syslogin'
    fill_in 'user[password]', with: 'secretsauce'
    click_button 'Logon'

    assert_current_path '/'
    assert_selector '#navbar a', text: 'syslogin'
    assert_selector '#navbar a', text: 'Logoff'
  end

  test 'a bad password leaves the operator back at the logon form' do
    visit '/users/logon'
    fill_in 'user[username]', with: 'syslogin'
    fill_in 'user[password]', with: 'wrong'
    click_button 'Logon'

    # Deliberately not asserting the notice text. do_logon sets
    # flash[:notice] = "Logon Failed!" and redirects to "/", which is itself
    # protected, so authorized? overwrites the flash with "Not authorized"
    # before anything renders it. The operator is told the wrong thing; that is
    # a controller redirect bug, not a markup one, so it is reported rather
    # than papered over here.
    assert_selector 'input[type=password][name="user[password]"]'
    assert_no_selector '#navbar a', text: 'Logoff'
  end

  test 'an unknown username does not sign anyone in' do
    visit '/users/logon'
    fill_in 'user[username]', with: 'nobody-at-all'
    fill_in 'user[password]', with: 'secretsauce'
    click_button 'Logon'

    assert_selector 'input[type=password][name="user[password]"]'
    assert_no_selector '#navbar a', text: 'Logoff'
  end

  test 'an anonymous visit to a protected page is sent to the logon form' do
    visit '/events'

    assert_selector '#notice', text: 'Not authorized'
    assert_selector 'input[type=password][name="user[password]"]'
  end

  test 'logoff drops the session and returns to the logon form' do
    sign_in
    visit '/'
    assert_selector '#navbar a', text: 'Logoff'

    click_link 'Logoff'

    assert_selector 'input[type=password][name="user[password]"]'
    assert_no_selector '#navbar a', text: 'Logoff'
  end
end

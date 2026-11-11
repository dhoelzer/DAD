require 'system_helper'

# The nav bar is generated from $_models and filtered by each model's hidden?,
# so it silently loses a tab when a model fails to load at boot or when a
# rights change goes wrong. Nothing else in the suite renders the layout, so
# these are the only tests that would notice.
class NavigationTest < SystemTest
  test 'an admin sees every top-level model tab' do
    sign_in
    visit '/'

    # Comment, Hunk and Right are hidden? true for everyone; Session,
    # Statistics, Preference and the rest are admin-only. This list is the
    # admin-visible set, so a model dropping out of $_models fails here.
    expected = %w[Alert Display Event Exclusion Job Preference Role Search
                  Service System User]
    expected.each do |tab|
      assert_selector "#navbar a", text: tab
    end
  end

  test 'a Viewer only sees the tabs their rights allow' do
    user = User.create!(username: 'viewonly', attempts: 0)
    right = Right.create!(name: 'Viewer', description: 'viewer')
    role = Role.create!(name: 'Viewers', description: 'viewers')
    role.rights << right
    user.roles << role
    user.save
    session = Session.create!(user: user, expiry: Time.now + 1.hour,
                              session_hash: SecureRandom.hex(16))
    page.driver.browser.set_cookie("sessionID=#{session.session_hash}; path=/")

    visit '/'

    assert_selector '#navbar a', text: 'Event'
    assert_selector '#navbar a', text: 'Alert'
    assert_no_selector '#navbar a', text: 'User'
    assert_no_selector '#navbar a', text: 'Display'
  end

  test 'every nav tab links to a page that renders' do
    sign_in
    visit '/'

    nav_links.each do |label|
      next if %w[Logoff].include?(label)
      next if label.start_with?('sysuser') # the current-user chip links nowhere

      click_link label
      assert_selector '#navbar'
      assert_selector 'h1', minimum: 1
    end
  end

  test 'the current user is shown in the nav bar' do
    sign_in(username: 'chipuser')
    visit '/'

    assert_selector '#navbar a', text: 'chipuser'
  end
end

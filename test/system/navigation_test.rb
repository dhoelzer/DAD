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

  test 'the primary tabs lead the bar in the intended order' do
    sign_in
    visit '/'

    # Order used to be $_models.sort, i.e. alphabetical by class name, which put
    # Event fourth and Search ninth. The first four are the everyday path, so
    # their position is now asserted rather than incidental.
    labels = page.all('#navbar > ul > li > a').map(&:text)
    assert_equal %w[Event Search System Service], labels.first(4)
  end

  test 'the Windows group holds AD and Windows targets, not the bar' do
    sign_in
    visit '/'

    # The group label is a <summary>, not a link: it opens the panel rather than
    # navigating anywhere.
    assert_selector '#navbar summary', text: 'Windows'

    # Both entries live inside the group's submenu, and both are shortened -- the
    # full class names used to be the tab labels. See nav_links in system_helper
    # for why the label comes from .native.text rather than Node#text.
    entries = all('#navbar details ul li a', visible: :all)
    assert_equal %w[AD Windows], entries.map { |a| a.native.text }
    assert_equal ['/active_directory_connections', '/windows_targets'],
                 entries.map { |a| a[:href] }

    # And they are no longer flat tabs anywhere in the bar.
    assert_no_selector '#navbar a', text: 'ActiveDirectoryConnection'
    assert_no_selector '#navbar a', text: 'WindowsTarget'
  end

  test 'the Windows group is marked active, not the tab, on a Windows page' do
    sign_in
    visit '/windows_targets'

    # Two li.active would break the bar's one-active-tab rule and make the
    # highlight ambiguous, so the group carries its own class while the child
    # entry holds the real active state.
    #
    # visible: :all throughout: the active entry is inside the closed panel, and
    # rack-test treats a closed <details> as hidden, so the default filter finds
    # nothing at all here rather than the wrong element.
    active = all('#navbar li.active', visible: :all)
    assert_equal 1, active.size
    assert_equal 'Windows', active.first.native.at('a').text
    assert_selector '#navbar li.group-active'
    assert_no_selector '#navbar li.group-inactive'

    # The bug this replaces: the layout compared params[:controller] against
    # model.pluralize.downcase, which yields "windowstargets" where the controller
    # path is "windows_targets", so these two tabs never highlighted at all.
    # Re-check the other one too, since both were broken the same way.
    visit '/active_directory_connections'
    assert_selector '#navbar li.group-active'
    assert_equal 'AD',
                 all('#navbar li.active a', visible: :all).first.native.text
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

      click_link label, visible: :all
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

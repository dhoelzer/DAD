require 'system_helper'

# Duplicate id attributes are invalid HTML, and browsers resolve getElementById
# and "#id" CSS selectors to the *first* match, so a repeated id silently makes
# every later element unaddressable.
#
# The app shipped with 209 of them across 17 pages. The nav bar emitted
# id="inactive" once per tab (10-11 per page), 23 views re-emitted the layout's
# id="notice", _alerts.html.erb used per-row ids for its column and criticality
# styling hooks, and #turbokiller / #comment were repeated ids that no CSS or JS
# ever referenced.
#
# This test is the guard. It is deliberately a scan rather than a set of
# per-page assertions: the failure mode is a view adding an id inside a loop,
# which is easy to write and invisible to a test that only checks the element it
# cares about exists.
class UniqueIdsTest < SystemTest
  # Pages that render a collection, plus a representative show page. The
  # collection pages are where a per-row id would show up.
  PAGES = %w[/alerts /events /users /systems /jobs /displays /searches
             /statistics /services /roles /rights /hunks /preferences
             /exclusions /sessions /windows_targets /alerts/1 /systems/1
             /active_directory_connections].freeze

  setup do
    sign_in
    # Several alerts at the SAME criticality: that is the combination that used
    # to emit id="criticality-5" once per row.
    system = System.create!(address: '10.0.0.9', name: 'duphost', description: 'd',
                            administrator: 'ops', contact_email: 'ops@example.com')
    service = Service.create!(name: 'dupsvc', description: 'd')
    3.times do |i|
      Alert.create!(system: system, service: service, criticality: 5,
                    generated: Time.now - i, closed: false,
                    description: "dup#{i}", short_description: "dup#{i}")
    end

    # The AD import preview renders one checkbox per candidate host. check_box_tag
    # derives an id from the field name, so 'selected_addresses[]' would emit the
    # same id on every row unless the view overrides it -- which is precisely the
    # loop-local id this test exists to catch.
    conn = ActiveDirectoryConnection.create!(
      name: 'dupad', host: 'dc01.corp.example.com', port: 636,
      bind_dn: 'CN=svc-dad,DC=corp,DC=example,DC=com', password: 'bindpw',
      search_base: 'DC=corp,DC=example,DC=com',
      polling_priority: PollingPriority.find_by(name: 'Priority 1'),
      poll_username: 'svc-poll', poll_password: 'winrmpw',
      event_logs: 'Application,System')
    @ad_batch = AdImportBatch.create!(active_directory_connection: conn, host_filter: 'all',
                                      candidates: 3.times.map do |i|
                                        { 'address' => "web0#{i}.corp.example.com",
                                          'name' => "web0#{i}",
                                          'operating_system' => 'Microsoft Windows 10 Pro',
                                          'host_class' => 'workstation',
                                          'domain_controller' => false,
                                          'already_present' => false }
                                      end)
  end

  test 'no page renders a duplicate id attribute' do
    # The batch id is not a fixture, so its path is built from the record.
    (PAGES + ["/ad_import_batches/#{@ad_batch.id}"]).each do |path|
      visit path

      ids = page.body.scan(/id\s*=\s*["']([^"']+)["']/).flatten
      duplicates = ids.tally.select { |_id, count| count > 1 }

      assert_empty duplicates,
                   "#{path} renders duplicate id attributes: #{duplicates.inspect}"
    end
  end

  # The nav bar is the highest-volume case: it renders one <li> per model, and
  # every one of them used id="active" or id="inactive".
  test 'the nav bar marks the current tab with a class, not a repeated id' do
    visit '/alerts'

    assert_selector '#navbar li.active', count: 1
    # Derived, not a fixed count: the layout renders one tab per visible model,
    # so a hardcoded number fails every time a model is added. What this guards
    # is that tabs are distinguished by class, not by how many there are.
    assert_operator all('#navbar li.inactive', visible: :all).size, :>, 0
    assert_empty page.body.scan(/id=['"](active|inactive)['"]/),
                 'nav tabs must use classes; only one tab is active'
  end

  # The layout owns #notice. Views that also emitted it were duplicating it.
  test 'the layout renders #notice exactly once' do
    %w[/users/1 /alerts/1 /systems/1].each do |path|
      visit path
      assert_equal 1, page.body.scan(/id=['"]notice['"]/).size,
                   "#{path} must not re-render the layout's #notice"
    end
  end
end

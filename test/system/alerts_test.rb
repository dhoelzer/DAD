require 'system_helper'

# The alert queue. _alerts.html.erb is the file with the most structural
# problems in the app (repeated ids used as styling hooks), so it is also the
# partial most likely to change during the UI work. These tests pin the
# behaviour that has to survive: the columns, the criticality styling hook, and
# the link into each alert.
class AlertsTest < SystemTest
  setup do
    @user = sign_in
    @system = System.create!(address: '10.0.0.7', name: 'web01',
                             description: 'web', administrator: 'ops',
                             contact_email: 'ops@example.com')
    @service = Service.create!(name: 'sshd', description: 'ssh')
    @alert = Alert.create!(system: @system, service: @service, criticality: 5,
                           generated: Time.now, closed: false,
                           description: 'root login from unexpected host',
                           short_description: 'root login from unexpected host')
  end

  test 'the alert queue lists open alerts with their columns' do
    visit '/alerts'

    assert_selector 'h1', text: 'Listing alerts'
    assert_selector '#alerts'
    assert_selector '#alerts', text: 'Generated'
    assert_selector '#alerts', text: 'System'
    assert_selector '#alerts', text: 'Service'
    assert_selector '#alerts', text: 'root login from unexpected host'
    assert_selector '#alerts', text: 'web01'
    assert_selector '#alerts', text: 'sshd'
  end

  test 'closed alerts are not listed' do
    @alert.update!(closed: true)
    visit '/alerts'

    assert_no_selector '#alerts', text: 'root login from unexpected host'
  end

  test 'each alert links to its detail page' do
    visit '/alerts'

    assert_selector "#alerts a[href='/alerts/#{@alert.id}']",
                    text: 'root login from unexpected host'
  end

  test 'the criticality of an alert drives its styling hook' do
    visit '/alerts'

    assert_selector '#criticality-5', visible: :all
  end

  test 'the acknowledge control is present for an open alert' do
    visit '/alerts'

    assert_selector "form[action='/alerts/#{@alert.id}/acknowledge']",
                    visible: :all
  end

  test 'acknowledging over html closes the alert and drops it from the queue' do
    visit '/alerts'

    # The button_to is remote: true, so a real browser acknowledges via JS and
    # re-renders the partial. rack-test does not run JS, so this posts the form
    # directly and follows the format.html branch of #acknowledge.
    page.driver.submit :post, "/alerts/#{@alert.id}/acknowledge", {}

    assert @alert.reload.closed?
    assert_no_selector '#alerts', text: 'root login from unexpected host'
  end

  test 'the acknowledge-all control is present' do
    visit '/alerts'

    assert_selector 'form.ackall-form', visible: :all
  end
end

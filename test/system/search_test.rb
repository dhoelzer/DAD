require 'system_helper'

# Search is the primary way an operator uses DAD. Results are rendered
# server-side into _search_results / _event_detail, so rack-test sees them --
# unlike the dashboard's AJAX-filled divs. These tests pin the result markup
# that the rest of the UI work touches.
class SearchTest < SystemTest
  setup do
    sign_in
    @event = create_searchable_event(
      hunks: 'web01 sshd[4242]: Accepted password for operator from 10.0.0.9 port 22',
      tokens: %w[web01 sshd Accepted password for operator]
    )
  end

  test 'a search renders matching events into the results container' do
    visit '/events/search?search_terms=sshd&timeframe=50000000&numresults=50'

    assert_selector '#events'
    assert_selector '#stats', text: '1 events match that search'
  end

  test 'a search for a term that does not exist returns no results' do
    visit '/events/search?search_terms=definitelynotaterm&timeframe=50000000&numresults=50'

    assert_selector '#stats', text: '0 events match that search'
  end

  test 'the result markup carries the system and the event text' do
    visit '/events/search?search_terms=sshd&timeframe=50000000&numresults=50'

    assert_selector '.event_detail'
    assert_selector '.system a', text: @event.system.display_name
    assert_selector '.event_detail a', text: 'sshd[4242]:'
  end

  test 'the search form keeps the terms that were searched for' do
    visit '/events/search?search_terms=sshd&timeframe=50000000&numresults=50'

    assert_selector 'input#search_terms[value="sshd"]'
  end

  test 'the elapsed-time header reports how long the search took' do
    visit '/events/search?search_terms=sshd&timeframe=50000000&numresults=50'

    assert_match(/Elapsed time: [\d.]+/, find('#stats', visible: :all).text)
  end

  test 'submitting the dashboard search form reaches the search action' do
    visit '/'

    fill_in 'search_terms', with: 'sshd'
    select 'All records', from: 'timeframe'
    click_button 'Search'

    assert_current_path '/events/search', ignore_query: true
    assert_selector '#stats', text: '1 events match that search'
  end
end

require 'test_helper'

class EventStateTest < ActiveSupport::TestCase
  SOURCE = File.expand_path('../../app/models/event.rb', __dir__)

  # The class body once declared the same 14 class variables and constants twice,
  # which is why every boot emitted "already initialized constant Event::CACHESIZE".
  # A duplicate declaration is not merely noisy: the second assignment silently
  # wins, so a value changed in one block is quietly reverted by the other.
  #
  # Checked at the source level rather than by capturing warnings, because these
  # are parser-level warnings that Warning.process does not see and that a
  # standalone load never reaches (the class body needs ActiveRecord loaded).
  test 'the class body declares each state variable exactly once' do
    body = File.read(SOURCE)

    # Everything before the first method definition is class-body state.
    state = body.split(/^\s*def /, 2).first

    names = state.scan(/^\s*(@@?[a-zA-Z_]\w*|CACHESIZE|DASHBOARD_MAX_EVENTS)\s*=/).flatten
    duplicates = names.group_by { |n| n }.select { |_, c| c.size > 1 }.keys

    assert_empty duplicates,
      "declared more than once in the class body: #{duplicates.sort.join(', ')}"
  end

  # Guards the check itself: if the scan ever stops matching the source, an empty
  # result would pass for the wrong reason.
  test 'the scan actually finds the state declarations' do
    body = File.read(SOURCE)
    state = body.split(/^\s*def /, 2).first
    names = state.scan(/^\s*(@@?[a-zA-Z_]\w*|CACHESIZE|DASHBOARD_MAX_EVENTS)\s*=/).flatten

    assert_includes names, '@@cached_words'
    assert_includes names, 'CACHESIZE'
    assert_operator names.size, :>=, 18
  end

  test 'resetCaches re-initialises every piece of ingest state' do
    Event.resetCaches

    assert_equal 0, Event.send(:class_variable_get, :@@timestamp_parse_failures)
    assert_equal(-1, Event.send(:class_variable_get, :@@nextEventID))
    assert_empty Event.send(:class_variable_get, :@@pendingEventValues)
    assert_empty Event.send(:class_variable_get, :@@events_words)
    assert_empty Event.send(:class_variable_get, :@@insertThreads)
    assert_empty Event.send(:class_variable_get, :@@cached_words)
    assert_empty Event.send(:class_variable_get, :@@system_cache)
    assert_empty Event.send(:class_variable_get, :@@service_cache)
  end
end

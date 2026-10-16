require 'test_helper'

# Guards against the same class of bug in both halves of the Event split: a
# piece of state assigned twice, where the second assignment silently wins.
class EventStateTest < ActiveSupport::TestCase
  EVENT = File.expand_path('../../app/models/event.rb', __dir__)
  INGESTOR = File.expand_path('../../app/models/event_ingestor.rb', __dir__)

  # The class body once declared the same 14 class variables and constants twice,
  # which is why every boot emitted "already initialized constant Event::CACHESIZE".
  # A duplicate declaration is not merely noisy: the second assignment silently
  # wins, so a value changed in one block is quietly reverted by the other.
  #
  # Checked at the source level rather than by capturing warnings, because these
  # are parser-level warnings that Warning.process does not see and that a
  # standalone load never reaches (the class body needs ActiveRecord loaded).
  test 'the Event class body declares each state variable exactly once' do
    names = state_declarations(File.read(EVENT))

    assert_includes names, '@@num_last_events'
    assert_includes names, 'DASHBOARD_MAX_EVENTS'
    duplicates = names.group_by { |n| n }.select { |_, c| c.size > 1 }.keys
    assert_empty duplicates,
      "declared more than once in the Event class body: #{duplicates.sort.join(', ')}"
  end

  # EventIngestor's state is initialised in resetCaches rather than the class
  # body, so the same bug there is a repeated assignment inside that method.
  # Catching it matters more now, not less: resetCaches is the single place the
  # ingest state is defined, so a duplicated line there is a real revert.
  test 'resetCaches assigns each piece of ingest state exactly once' do
    body = File.read(INGESTOR)
    initialiser = body[/def self\.resetCaches.*?\n  end/m]
    refute_nil initialiser, 'resetCaches not found in event_ingestor.rb'

    names = initialiser.scan(/^\s*(@@?[a-zA-Z_]\w*)\s*=/).flatten
    assert_operator names.size, :>=, 15,
      'the scan stopped matching resetCaches; it would pass for the wrong reason'
    duplicates = names.group_by { |n| n }.select { |_, c| c.size > 1 }.keys
    assert_empty duplicates,
      "assigned more than once in resetCaches: #{duplicates.sort.join(', ')}"
  end

  # The split is only worth having if the read side no longer carries ingest
  # state. Event keeps the dashboard feed counter; everything the pipeline needs
  # belongs to EventIngestor.
  test 'ingest state lives in EventIngestor, not on the Event model' do
    event_state = state_declarations(File.read(EVENT))

    %w[@@pendingEventValues @@events_words @@nextEventID @@cached_words
       @@insertThreads @@system_cache @@service_cache].each do |name|
      refute_includes event_state, name,
        "#{name} is ingest state and belongs in EventIngestor"
    end
  end

  # Asserted through EventIngestor's introspection API rather than by reaching
  # for class variables: the previous version named the storage slots, so any
  # change to how the state is held broke it even when behaviour was identical.
  test 'resetCaches re-initialises every piece of ingest state' do
    EventIngestor.resetCaches

    assert_equal 0, EventIngestor.timestamp_parse_failures
    assert_equal(-1, EventIngestor.next_event_id)
    assert_equal 0, EventIngestor.pending_count
    assert_equal 0, EventIngestor.staged_words_count
    assert_equal 0, EventIngestor.in_flight_count
    assert_equal 0, EventIngestor.cached_word_count
  end

  private

  # Everything before the first method definition is class-body state.
  def state_declarations(body)
    state = body.split(/^\s*def /, 2).first
    state.scan(/^\s*(@@?[a-zA-Z_]\w*|CACHESIZE|DASHBOARD_MAX_EVENTS)\s*=/).flatten
  end
end

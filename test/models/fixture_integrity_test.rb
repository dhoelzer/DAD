require 'test_helper'

# Every fixture other than systems/services/events/alerts/users hardcoded
# system_id: 1, service_id: 1, user_id: 1 and so on, but Rails gives fixtures
# hashed ids, so no row had id 1 and every one of those keys dangled. The
# visible symptom was a 500 on /jobs: Job#user was nil and jobs/index.html.erb
# called job.user.username. Nothing caught it because no test rendered that
# page.
#
# Rather than trust each new fixture to use labeled associations, assert the
# invariant directly: no fixture foreign key points at a missing parent.
class FixtureIntegrityTest < ActiveSupport::TestCase
  fixtures :all

  # column => the model it references.
  PARENTS = {
    'system_id' => 'System',
    'service_id' => 'Service',
    'user_id' => 'User',
    'alert_id' => 'Alert',
    'last_event_id' => 'Event'
  }.freeze

  CHILDREN = %w[Event Alert Job Comment Search Statistic].freeze

  test 'no fixture foreign key points at a missing parent' do
    CHILDREN.each do |name|
      klass = name.constantize
      PARENTS.each do |column, parent_name|
        next unless klass.column_names.include?(column)

        parent = parent_name.constantize
        referenced = klass.pluck(column).compact.uniq
        missing = referenced - parent.pluck(:id)
        assert_empty missing,
          "#{name}.#{column} references rows that no fixture provides: #{missing.inspect}"
      end
    end
  end
end

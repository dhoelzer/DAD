require 'test_helper'

# username had no uniqueness at the model layer and no unique index in the
# database, so two accounts could be created with the same name. do_logon uses
# find_by, so the lowest id won and the second account could never sign in --
# silently, with no error anywhere. Blank and nil usernames were also accepted.
class UsernameIntegrityTest < ActiveSupport::TestCase
  test 'a duplicate username is rejected by the model' do
    User.create!(username: 'jane-doe', attempts: 0)
    dupe = User.new(username: 'jane-doe', attempts: 0)
    refute dupe.valid?
    assert_match(/taken|already/i, dupe.errors.full_messages.join)
  end

  test 'a blank username is rejected' do
    refute User.new(username: '', attempts: 0).valid?,
      'an account with an empty username can be reached by submitting the login ' \
      'form with the username field left blank'
    refute User.new(username: nil, attempts: 0).valid?
  end

  test 'the database rejects a duplicate username even if the model is bypassed' do
    User.create!(username: 'db-guard', attempts: 0)
    assert_raises(ActiveRecord::RecordNotUnique) do
      # insert_all! rather than insert_all: the non-bang version uses
      # ON CONFLICT DO NOTHING and would swallow the very violation here.
      User.insert!({ username: 'db-guard', attempts: 0 })
    end
  end

  test 'users.username carries a unique index' do
    on_name = ActiveRecord::Base.connection.indexes(:users).select do |i|
      i.columns.include?('username')
    end
    refute_empty on_name, 'users.username must be indexed: it is looked up per login'
    assert on_name.any?(&:unique), 'the index on users.username must be unique'
  end
end

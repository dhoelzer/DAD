require 'system_helper'

# /jobs is a nav-bar tab that returned a 500 before the views were made
# nil-safe: jobs/index.html.erb called job.user.username unconditionally, and
# jobs.user_id is nullable, so an unassigned job raised
# ActionView::Template::Error. No controller test caught it because none of
# them render the view.
class JobsTest < SystemTest
  setup do
    @user = sign_in
  end

  test 'the job list renders with its columns' do
    Job.create!(name: 'nightly sweep', description: 'sweep the archive',
                user: @user, script: 'prune_words', frequency: 3600,
                next_run: Time.now + 3600)

    visit '/jobs'

    assert_selector 'h1', text: /Listing jobs/i
    assert_selector 'table', text: 'nightly sweep'
    assert_selector 'table', text: @user.username
  end

  test 'a job with no assigned user still renders' do
    Job.create!(name: 'unassigned sweep', description: 'no owner',
                user: nil, script: 'prune_words', frequency: 3600,
                next_run: Time.now + 3600)

    visit '/jobs'

    assert_selector 'table', text: 'unassigned sweep'
  end

  test 'a job detail page renders its fields' do
    job = Job.create!(name: 'detail sweep', description: 'the description',
                      user: @user, script: 'prune_words', frequency: 3600,
                      next_run: Time.now + 3600)

    visit "/jobs/#{job.id}"

    assert_selector 'p', text: 'detail sweep'
    assert_selector 'p', text: 'the description'
    assert_selector 'p', text: @user.username
    assert_selector "a[href='/jobs/#{job.id}/edit']", text: 'Edit'
  end

  test 'a job detail page renders when the job has no user' do
    job = Job.create!(name: 'ownerless', description: 'no owner',
                      user: nil, script: nil, frequency: 3600,
                      next_run: Time.now + 3600)

    visit "/jobs/#{job.id}"

    assert_selector 'p', text: 'ownerless'
    # The User block is skipped entirely rather than rendering "nil".
    assert_selector 'p', text: 'none (disabled)'
  end
end

require 'test_helper'

# The Jobs screen used to accept arbitrary Ruby, evaluated by scheduler.rb as the
# scheduler user. It now offers a fixed handler list; these cover the form and the
# create boundary.
class JobsControllerTest < ActionController::TestCase
  tests JobsController

  setup do
    @request.env['HTTPS'] = 'on'
    right = Right.create!(name: "Admin", description: "admin")
    role = Role.create!(name: "Admins#{Time.now.to_i}", description: "admins")
    role.rights << right
    @user = User.create!(username: "admin#{Time.now.to_i}", attempts: 0)
    @user.store_password("secretsauce")
    @user.roles << role
    @session_hash = SecureRandom.hex(16)
    Session.create!(user: @user, expiry: Time.now + 1.hour, session_hash: @session_hash)
    cookies[:sessionID] = @session_hash
  end


  # The #test action read @job.script but was not in set_job's before_action list,
  # so it 500'd as routed. It had no view and duplicated what #show already
  # displays, so the action and its route are gone.
  test 'the removed test action is not reachable' do
    job = Job.create!(name: 'j', script: 'prune_words', frequency: 3600, user: @user)
    assert_raises(ActionController::UrlGenerationError) { get :test, params: { id: job.id } }
  end
  test "the form offers registered operations, not a script editor" do
    get :new
    assert_response :success
    assert_select "select#job_script"
    assert_match(/prune_words/, response.body)
    refute_match(/CodeMirror/, response.body)
  end

  test "creating a job with a registered handler succeeds" do
    assert_difference "Job.count" do
      post :create, params: { job: { name: "nightly", script: "prune_words", frequency: 3600 } }
    end
    assert_equal "prune_words", Job.last.script
  end

  test "creating a job with Ruby is rejected and nothing is executed" do
    marker = Rails.root.join("tmp_pwned_job")
    File.delete(marker) if File.exist?(marker)
    assert_no_difference "Job.count" do
      post :create, params: { job: { name: "evil", script: "File.write('#{marker}','ran')", frequency: 60 } }
    end
    refute File.exist?(marker)
  end
end

require 'system_helper'

# The error summary is now one shared partial rendered by 14 forms. Before this
# suite nothing at all asserted that it renders, so a broken partial would have
# shipped with every test still green.
#
# Only two of the fourteen models can actually reach it. The rest have no
# validations, and config/application.rb deliberately does not call
# load_defaults, so belongs_to_required_by_default is off and a blank Alert or
# Display saves cleanly. User validates username presence and Job validates
# frequency numericality, so those are the two paths exercised here.
class FormErrorsTest < SystemTest
  test 'an invalid user form renders the shared error summary' do
    sign_in
    visit '/users/new'
    fill_in 'Username', with: ''
    click_button 'Create User'

    assert_selector '#error_explanation'
    within('#error_explanation') do
      # The noun comes from model_name.human, not a per-form string, so this
      # asserts the derivation as well as the markup.
      assert_text '1 error prohibited this user from being saved:'
      assert_selector 'li', text: "Password can't be blank"
    end
    # Rails wraps the offending control itself; the partial does not emit this.
    assert_selector '.field_with_errors input#user_password'
  end

  test 'an invalid job form renders the same summary with its own model name' do
    job = Job.first
    assert job, 'jobs fixture missing'
    sign_in

    visit "/jobs/#{job.id}/edit"
    fill_in 'Frequency', with: 'not-a-number'
    click_button 'Update Job'

    assert_selector '#error_explanation'
    within('#error_explanation') do
      assert_text '1 error prohibited this job from being saved:'
      assert_selector 'li', text: 'Frequency must be a positive number of seconds'
    end
  end

  # A form with no errors must render no summary at all -- the guard lives in
  # the shared partial, so this is what proves the guard survived extraction.
  test 'a valid form renders no error summary' do
    sign_in
    visit '/users/new'
    assert_no_selector '#error_explanation'

    visit '/jobs/new'
    assert_no_selector '#error_explanation'
  end

  # The partial is shared, so it has to work for every form that renders it,
  # including the twelve whose models cannot currently produce an error.
  # Rendering it directly is the only way to cover those without inventing
  # validations they do not have.
  test 'the partial renders for every model whose form uses it' do
    %w[Alert Comment Display Exclusion Hunk Job Preference Right Role Search
       Service Statistic System User].each do |name|
      record = name.constantize.new
      record.errors.add(:base, 'a synthetic failure')
      html = ApplicationController.render(
        partial: 'shared/error_explanation',
        locals: { record: record })
      assert_includes html, 'a synthetic failure',
                      "shared partial does not render errors for #{name}"
      assert_includes html, "prohibited this #{name.downcase} from being saved:",
                      "shared partial names the model wrong for #{name}"
    end
  end
end

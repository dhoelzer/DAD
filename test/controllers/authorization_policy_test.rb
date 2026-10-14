require 'test_helper'

# The policy lives in ApplicationController constants rather than in per-controller
# authorized? overrides, so it can be checked without issuing requests.
class AuthorizationPolicyTest < ActiveSupport::TestCase
  def controller_classes
    Dir[Rails.root.join("app/controllers/*_controller.rb")].map do |f|
      File.basename(f, ".rb").camelize.safe_constantize
    end.compact
  end

  test "every controller declares rights or is intentionally public" do
    names = controller_classes.map { |k| k.name.sub("Controller", "").underscore }
                              .reject { |c| c == "application" }
    declared = (ApplicationController::CONTROLLER_RIGHTS.keys +
                ApplicationController::PUBLIC_ACTIONS.keys).uniq
    assert_equal [], (names - declared), "controllers with no declared rights"
  end

  # Fail-closed: an undeclared controller grants nothing.
  test "an unmapped controller grants nothing" do
    assert_nil ApplicationController.required_rights("nonexistent", "index")
  end

  # nil from required_rights means "denied"; public access is a separate concept
  # expressed by PUBLIC_ACTIONS and short-circuited in #authorized?.
  test "logon actions are listed as public" do
    assert_equal %w[logon do_logon logoff], ApplicationController::PUBLIC_ACTIONS["users"]
  end

  test "saving a search needs Detective, reading one needs Viewer" do
    assert_equal %w[Detective], ApplicationController.required_rights("searches", "create")
    assert_equal %w[Detective], ApplicationController.required_rights("searches", "destroy")
    assert_equal %w[Viewer], ApplicationController.required_rights("searches", "index")
    assert_equal %w[Viewer], ApplicationController.required_rights("searches", "show")
  end

  test "preferences require Admin" do
    assert_equal %w[Admin], ApplicationController.required_rights("preferences", "update")
  end

  # The gate must not be a routable action: a public #authorized? was reachable
  # as GET /users/authorized.
  test "authorized? is private and never an action method" do
    controller_classes.each do |k|
      refute k.public_instance_methods(false).include?(:authorized?),
             "#{k.name} defines a public authorized?"
      refute k.action_methods.include?("authorized?"),
             "#{k.name} routes authorized?"
    end
  end
end

require 'test_helper'

# JobHandler is the registry that replaced eval(job.script) in scheduler.rb.
class JobHandlerTest < ActiveSupport::TestCase
  test "names lists every registered handler, sorted" do
    names = JobHandler.names
    assert_includes names, "prune_words"
    assert_equal names.sort, names
  end

  test "known? accepts registered names only" do
    assert JobHandler.known?("reset_stats")
    refute JobHandler.known?("system('rm -rf /')")
    refute JobHandler.known?(nil)
  end

  test "perform runs a registered handler and returns a summary" do
    assert_equal "reset throughput clock", JobHandler.perform("reset_stats")
  end

  test "perform raises for an unknown name rather than evaluating it" do
    assert_raises(JobHandler::UnknownHandler) do
      JobHandler.perform("File.write('tmp_probe','ran')")
    end
    refute File.exist?(Rails.root.join("tmp_probe"))
  end

  test "a Job is invalid unless its script names a handler" do
    job = Job.new(:name => "x", :script => "puts 1", :frequency => 60)
    refute job.valid?
    assert_match(/must be one of/, job.errors[:script].join)
  end

  test "a Job with a registered handler is valid" do
    job = Job.new(:name => "x", :script => "prune_words", :frequency => 60)
    assert job.valid?, job.errors.full_messages.join
  end

  test "a blank script is allowed so existing rows still save" do
    assert Job.new(:name => "x", :frequency => 60).valid?
  end

  # Every handler must resolve its constants in the app's own boot environment.
  #
  # This caught a real defect: 'poll_windows_events' called WindowsPollCycle,
  # which lives in lib/. This app has no autoload path for lib/ -- models are
  # required explicitly in config/application.rb and lib files are required by
  # hand -- so the constant was undefined at runtime and the seeded Job raised
  # NameError on every scheduler cycle. JobScheduler rescues Exception and raises
  # a criticality-5 Alert, so the poller never ran while the Job looked healthy in
  # the Jobs list.
  #
  # The handlers above only exercise reset_stats, which is why this slipped
  # through. Asserting NameError specifically (rather than "the handler
  # succeeds") keeps the test independent of what each handler does: disk_utilization
  # legitimately reports nil where there is no archive partition to measure, and
  # that is not a load failure.
  test "every registered handler resolves its constants at runtime" do
    refute_empty JobHandler::HANDLERS

    JobHandler::HANDLERS.each do |name, handler|
      begin
        handler.call(nil)
      rescue NameError => e
        # NoMethodError is a subclass of NameError. A missing METHOD on a nil
        # receiver means the handler ran and hit an absent fixture (several
        # depend on Display or Event rows this test does not create); a missing
        # CONSTANT means the code itself never loaded. Only the second is a
        # require problem, and it is the one that was silently broken.
        next if e.is_a?(NoMethodError)
        flunk "handler #{name.inspect} references an undefined constant: #{e.message}. " \
              'lib/ is not autoloaded in this app -- require the file it lives in.'
      rescue StandardError
        # A handler failing for an environmental reason is out of scope here;
        # this test is only about whether the code loads.
      end
    end
  end
end

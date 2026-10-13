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
end

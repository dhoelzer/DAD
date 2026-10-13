require 'test_helper'

# DisplayRule interprets the declarative display_script spec that replaced the
# eval(display_script) sink in Event#parsed.
class DisplayRuleTest < ActiveSupport::TestCase
  LINE = "Apr 12 10:22:01 host sshd[1234]: Failed password for root from 10.0.0.5 port 22"

  test "fields selects 1-based positions in the given order" do
    assert_equal "host sshd[1234]:", DisplayRule.apply("fields 4,5", LINE)
  end

  test "regex emits capture groups from the raw line" do
    assert_equal "10.0.0.5", DisplayRule.apply("regex (\\d+\\.\\d+\\.\\d+\\.\\d+)", LINE)
  end

  test "regex with no match leaves the line unchanged" do
    assert_equal LINE, DisplayRule.apply("regex zzz(never)", LINE)
  end

  test "label prefixes a selected field" do
    assert_equal "from: 10.0.0.5", DisplayRule.apply("fields 11\nlabel 1=from: ", LINE)
  end

  test "join sets the separator" do
    assert_equal "host,sshd[1234]:", DisplayRule.apply("fields 4,5\njoin ,", LINE)
  end

  test "comments and blank lines are ignored" do
    assert_equal "host sshd[1234]:", DisplayRule.apply("# pick the host\n\nfields 4,5\n", LINE)
  end

  test "an empty spec returns the line unchanged" do
    assert_equal LINE, DisplayRule.apply("", LINE)
    assert_equal LINE, DisplayRule.apply(nil, LINE)
  end

  test "a spec that selects nothing returns the line unchanged" do
    assert_equal LINE, DisplayRule.apply("fields 999", LINE)
  end

  test "validate accepts a good spec" do
    assert_equal [], DisplayRule.validate("fields 1,2\njoin ,")
  end

  test "validate rejects an unknown directive with its line number" do
    errs = DisplayRule.validate("fields 1\neval 2+2")
    assert_equal 1, errs.size
    assert_match(/line 2/, errs.first)
  end

  test "validate rejects malformed fields, label and regex" do
    assert_match(/fields/, DisplayRule.validate("fields a,b").first)
    assert_match(/label/, DisplayRule.validate("label 3").first)
    assert_match(/bad pattern/, DisplayRule.validate("regex (unclosed").first)
  end

  # The whole point of the change: a script that used to be Ruby must not run.
  test "ruby in a display script is never evaluated" do
    spec = "fields 1\n`touch tmp_eval_probe`\nsystem('touch tmp_eval_probe')\nFile.write('tmp_eval_probe','ran')"
    out = DisplayRule.apply(spec, LINE)
    assert_equal LINE, out, "malicious spec should degrade to the raw line"
    refute File.exist?(Rails.root.join("tmp_eval_probe"))
  end

  test "apply does not raise on a spec that fails to parse" do
    assert_equal LINE, DisplayRule.apply("this is not a directive", LINE)
  end
end

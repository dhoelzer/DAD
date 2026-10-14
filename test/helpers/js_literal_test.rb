require 'test_helper'

# js_literal is the escaping boundary for every value interpolated into a
# .js.erb template. These pin the properties the templates rely on.
class JsLiteralTest < ActionView::TestCase
  include ApplicationHelper

  test "escapes a double quote so it cannot close a JS string literal" do
    assert_equal '"a\";alert(1);//"', js_literal('a";alert(1);//')
  end

  # Rails HTML-escapes <%= %> in a JS template, which neutralises a quote but
  # leaves a backslash alone. A trailing backslash used to turn the generated
  # script into a syntax error.
  test "escapes backslashes" do
    assert_equal '"\\\\"', js_literal('\\')
  end

  test "escapes newlines" do
    assert_equal '"a\nb"', js_literal("a\nb")
  end

  # A </script> sequence would terminate an inlined <script> block.
  test "encodes HTML-sensitive characters" do
    out = js_literal('</script><img onerror=1>')
    refute_includes out, '</script>'
    assert_includes out, '\u003c'
  end

  test "nil becomes an empty JS string, not null" do
    assert_equal '""', js_literal(nil.to_s)
  end

  test "renders arrays of pairs as JS array literals" do
    assert_equal '[["sshd",3]]', js_literal([["sshd", 3]])
  end

  # The result must be html_safe or Rails would escape the output a second time.
  test "output is html_safe" do
    assert js_literal('a"b').html_safe?
  end

  test "output round-trips through a JS/JSON parser" do
    payload = 'a";alert(1);//' + 0x5c.chr + [0x2028].pack("U*") + "</script>"
    assert_equal [payload, 1], JSON.parse(js_literal([payload, 1]))
  end
end

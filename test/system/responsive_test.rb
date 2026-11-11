require 'system_helper'

# Without a viewport meta tag a phone renders the page at a ~980px virtual
# width and then scales it down, so the nav bar and the alert queue are
# legible only by pinching. The tag is what makes width-based CSS apply at
# the device's actual width.
class ResponsiveTest < SystemTest
  test 'every page declares a viewport' do
    sign_in
    visit '/'

    assert_selector 'meta[name="viewport"]', visible: :all
    meta = page.find('meta[name="viewport"]', visible: :all)['content']
    assert_includes meta, 'width=device-width',
                    'viewport must track the device width, not a fixed virtual width'
  end

  # The responsive rules are only correct if the desktop rules they override
  # are still the ones that apply above the breakpoint. rack-test has no layout
  # engine, so this is the cheapest check that the containment holds.
  test 'the responsive rules live inside a media query' do
    css = File.read(Rails.root.join('app/assets/stylesheets/application.css'))

    query = css[/@media[^{]*\{/]
    assert query, 'application.css must scope narrow-screen rules in a media query'

    # Everything after the opening @media has to be inside its block: a rule
    # that falls out of it applies at every width and changes desktop rendering.
    open_at = css.index(query)
    depth = 0
    closed_at = nil
    css[open_at..].each_char.with_index do |c, i|
      depth += 1 if c == '{'
      if c == '}'
        depth -= 1
        if depth.zero?
          closed_at = open_at + i
          break
        end
      end
    end
    assert closed_at, 'the @media block is not balanced'

    trailing = css[(closed_at + 1)..].gsub(/\/\*.*?\*\//m, '').strip
    assert_empty trailing,
                 'rules after the @media block apply at every width: ' \
                 "#{trailing[0, 120]}"
  end
end

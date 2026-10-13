# Interpreter for Display#display_script.
#
# Replaces the previous design, in which Event#parsed ran
# eval(display_script) and then called the parse_event method that script was
# expected to define -- so editing a Display from the web UI was arbitrary Ruby
# execution as the web process user (RECOMMENDATIONS.md 1.2).
#
# A display_script is now a line-oriented declarative spec that is *parsed*, never
# executed. It reformats a raw log line into the token string the event views
# render as clickable search links.
#
# Grammar (one directive per line, '#' starts a comment):
#
#   fields 1,2,5        emit these 1-based positional fields, in this order
#   regex PATTERN       emit PATTERN's capture groups instead of positions
#   label 3=proto       prefix field 3 with "proto:"
#   join ,              join emitted tokens with this separator (default: space)
#
# Unknown directives and malformed specs are collected by #validate; #apply
# returns the raw line unchanged rather than raising, so a bad rule degrades to
# "no reformatting" instead of breaking the dashboard.
class DisplayRule
  DIRECTIVES = %w[fields regex label join].freeze

  # A spec error, carrying the offending line number for the form to display.
  class Invalid < StandardError
    attr_reader :line
    def initialize(msg, line = nil)
      super(msg)
      @line = line
    end
  end

  # Parses +script+ into a directive list, raising DisplayRule::Invalid on the
  # first malformed line.
  def self.parse(script)
    directives = []
    (script.to_s.split("\n", -1)).each_with_index do |raw, i|
      line = raw.include?('#') ? raw[0...raw.index('#')] : raw
      line = line.sub(/\A\s+/, '')
      next if line.strip.empty?
      # Capture the argument verbatim: trailing whitespace is significant for
      # `join` and `label`, so this must not go through String#split.
      m = line.match(/\A(\S+)(?:\s(.*))?\z/)
      directive, arg = m[1], m[2].to_s
      unless DIRECTIVES.include?(directive.to_s)
        raise Invalid.new("unknown directive #{directive.inspect}", i + 1)
      end
      directives << compile(directive, arg, i + 1)
    end
    directives
  end

  # Returns an Array of human-readable problems, empty when the spec is valid.
  # Used by Display's model validation so a bad spec is rejected on save rather
  # than discovered while rendering events.
  def self.validate(script)
    parse(script)
    []
  rescue Invalid => e
    ["display script line #{e.line}: #{e.message}"]
  end

  # Applies +script+ to the raw log line +hunks+, returning the display string.
  #
  # Never evaluates Ruby. A spec that fails to parse, or that selects no fields,
  # returns +hunks+ unchanged.
  def self.apply(script, hunks)
    begin
      directives = parse(script)
    rescue Invalid
      return hunks
    end
    return hunks if directives.empty?
    new(hunks).render(directives)
  end

  def self.compile(directive, arg, line)
    case directive
    when 'fields'
      indices = arg.split(',').map { |t| Integer(t.strip) rescue nil }
      raise Invalid.new('fields needs a comma-separated list of positive integers', line) if indices.empty? || indices.any?(&:nil?) || indices.any? { |n| n < 1 }
      [:fields, indices]
    when 'regex'
      raise Invalid.new('regex needs a pattern', line) if arg.empty?
      begin
        [:regex, Regexp.new(arg)]
      rescue RegexpError => e
        raise Invalid.new("bad pattern: #{e.message}", line)
      end
    when 'label'
      idx, text = arg.split('=', 2)
      n = Integer(idx) rescue nil
      raise Invalid.new('label needs INDEX=TEXT with a positive integer INDEX', line) if n.nil? || n < 1 || text.nil? || text.empty?
      [:label, n, text]
    when 'join'
      raise Invalid.new('join needs a separator', line) if arg.empty?
      [:join, arg]
    end
  end
  private_class_method :compile

  def initialize(hunks)
    @raw = hunks.to_s
    @fields = @raw.split(/ +/)
  end

  def render(directives)
    tokens = nil
    labels = {}
    sep = ' '
    directives.each do |d|
      case d[0]
      when :fields
        tokens = d[1].map { |n| @fields[n - 1] }.compact
      when :regex
        m = d[1].match(@raw)
        tokens = m.nil? ? [] : (m.captures.empty? ? [m[0]] : m.captures)
      when :label
        labels[d[1]] = d[2]
      when :join
        sep = d[1]
      end
    end
    return @fields.join(' ') if tokens.nil? || tokens.empty?
    tokens.each_with_index.map { |t, i| labels.key?(i + 1) ? "#{labels[i + 1]}#{t}" : t }.join(sep)
  end
end

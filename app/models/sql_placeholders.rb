# Positional placeholders for hand-written SQL, across both adapters this app runs.
#
# Every raw query in the app is written with SQLite's `?` and passed to
# exec_query along with an array of binds. That works on SQLite and fails on
# Postgres, which rejects `?` outright:
#
#   PG::SyntaxError: ERROR:  syntax error at or near ")"
#
# The failure is not confined to one query. It reached the ingest path --
# EventIngestor.insertStatement builds the bulk INSERTs for events and events_words --
# which meant production could not insert a single event while the whole suite
# stayed green, because dev and test only ever run SQLite.
#
# Rather than fork every query per adapter, translate at the one place raw SQL
# meets the driver. Queries keep the `?`-and-binds form Rails documents, and the
# adapter gets whatever it actually wants.
#
# Verified on both engines: Postgres binds $N by *number*, SQLite binds by *order
# of appearance*, so numbering the placeholders left to right is correct on both.
# (SQLite ignores the digits; do not reorder placeholders within a query and
# expect either adapter to agree.)
module SqlPlaceholders
  # Runs +sql+ on the current connection with +binds+, translating placeholders
  # first. Prefer this over calling exec_query directly: it is what keeps a query
  # written for one adapter from silently breaking on the other.
  def self.query(sql, binds = [], name = 'SQL')
    ActiveRecord::Base.connection.exec_query(translate(sql), name, binds)
  end

  # Rewrites each `?` as $1, $2, ... in left-to-right order, but only when the
  # connection needs it. Returns the input unchanged on adapters that accept `?`.
  #
  # Known limitation: Postgres also uses `?` as an operator (jsonb key existence).
  # Nothing in this app queries jsonb; if it ever does, that query needs its own
  # path rather than this translation.
  def self.translate(sql)
    return sql if ActiveRecord::Base.connection.adapter_name != 'PostgreSQL'
    number_placeholders(sql)
  end

  # The rewriting itself, with no adapter in the way so it can be tested under
  # either engine.
  #
  # Only placeholders outside quoted literals are touched: a `?` inside 'a?b' is
  # data, not a bind slot.
  def self.number_placeholders(sql)
    return sql unless sql.include?('?')

    out = +''
    position = 0
    quote = nil
    sql.each_char do |char|
      if quote
        out << char
        quote = nil if char == quote
      elsif char == "'" || char == '"'
        quote = char
        out << char
      elsif char == '?'
        position += 1
        out << "$#{position}"
      else
        out << char
      end
    end
    out
  end
end

# EXPLAIN as one flat string, for tests that assert an index is usable.
#
# These tests guard plans rather than results: a missing or mis-ordered index
# leaves every query returning correct rows, just slowly, which is how the
# sessions and events_words findings shipped in the first place. Asserting on the
# plan is the only way to catch the index being dropped or renamed.
#
# enable_seqscan = off is deliberate. On a test-sized table the planner is
# entitled to prefer a sequential scan -- it genuinely is cheaper when the table
# holds a handful of rows -- so a test that asserted the planner's cost choice
# would be asserting a guess and would break as soon as the fixtures changed.
# Turning scans off asks the narrower question the findings were about: can this
# index serve this query shape at all? If it were dropped, or its columns
# reordered so the predicate no longer matched, this plan could not be produced.
module QueryPlan
  # +sql+ uses `?` placeholders with +binds+, the same form the app's raw queries
  # use; SqlPlaceholders adapts them to what the driver wants.
  def explain(sql, binds = [])
    conn = ActiveRecord::Base.connection
    conn.execute('SET enable_seqscan = off')
    begin
      conn.exec_query('EXPLAIN ' + SqlPlaceholders.translate(sql), 'EXPLAIN', binds)
          .to_a.map { |row| row['QUERY PLAN'].to_s }.join("\n")
    ensure
      conn.execute('RESET enable_seqscan')
    end
  end
end

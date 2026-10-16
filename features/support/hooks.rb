# Event keeps word/system/service row IDs in class-level caches. DatabaseCleaner
# rolls the DB back between scenarios but cannot reach those caches, so the next
# scenario would reuse dangling IDs. Clear them before every scenario.
Before do
  EventIngestor.resetCaches
end

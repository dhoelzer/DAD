# Adds the archive-partition free-space floor that EventPartitionBackup prunes to.
#
# Retention archives a month to offline_storage before dropping its partition,
# and nothing used to prune those archives: on a long-lived install the directory
# grows without bound, the disk fills, archiving starts failing, and partitions
# stop being dropped -- so the database grows instead of the disk filling.
#
# Stored on preferences rather than in the environment because it is an operator
# decision that belongs next to the other dashboard settings, and the Preferences
# screen is already Admin-gated (ApplicationController::CONTROLLER_RIGHTS).
#
# NULL means "no floor", which disables pruning. Deliberately not 0-as-default
# with a positive fallback: pruning deletes the only copy of a month's rows, so
# it has to be switched on on purpose.
class AddArchiveFreeSpacePercentToPreferences < ActiveRecord::Migration[8.1]
  def up
    add_column :preferences, :archiveFreeSpacePercent, :integer
  end

  def down
    remove_column :preferences, :archiveFreeSpacePercent
  end
end

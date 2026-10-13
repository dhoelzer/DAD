# Retires Job rows written under the old eval(job.script) design.
#
# Before the JobHandler registry existed, every Job#script held arbitrary Ruby
# that scheduler.rb evaluated. Those scripts cannot be translated into registry
# names, and leaving them in place would make the scheduler raise UnknownHandler
# and raise a Critical Alert on every cycle forever.
#
# So every pre-existing Job is made inert: script is cleared and next_run is set
# to NULL, which the scheduler's `next_run < ?` predicate never matches. An
# operator who still wants the task re-enables it deliberately by choosing a
# registered handler.
class RetireLegacyJobScripts < ActiveRecord::Migration
  def up
    execute "UPDATE jobs SET script = NULL, next_run = NULL"
  end

  def down
    # The original Ruby is discarded on purpose; it cannot be restored.
    raise ActiveRecord::IrreversibleMigration
  end
end

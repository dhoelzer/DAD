# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rake db:seed (or created alongside the db with db:setup).
#
# Examples:
#
#   cities = City.create([{ name: 'Chicago' }, { name: 'Copenhagen' }])
#   Mayor.create(name: 'Emanuel', city: cities.first)
# The initial administrator. Its password is NOT committed: it comes from
# DAD_ADMIN_PASSWORD, and seeding fails loudly if that is unset, rather than
# silently creating a well-known "Password1" account on a public host.
#   DAD_ADMIN_PASSWORD='<a-long-random-passphrase>' rake db:seed
admin_password = ENV["DAD_ADMIN_PASSWORD"]
raise "Refusing to seed: set DAD_ADMIN_PASSWORD to the initial admin password." if admin_password.nil? || admin_password.empty?

user = User.new
user.username = ENV["DAD_ADMIN_USER"] || "admin"
user.attempts = 0
user.store_password(admin_password)
user.save
right=Right.new
right.name="Admin"
right.description="This right grants complete and absolute access to everything.  This should only ever be assigned to the Administrators role."
right.save
role=Role.new
role.name="Administrators"
role.description="This role has only one right, 'Admin'.  This grants complete access to absolutely everything.  Nothing is hidden from your sight.  Only one or two users should ever have this role!!"
role.save
role.rights << right
role.save
user.roles << role
user.save
right = Right.new
right.name = "Viewer"
right.description = "Gives the possessor the ability to view events and alerts"
right.save
right = Right.new
right.name = "Commentator"
right.description = "Gives the possessor the ability to comment on alerts"
right.save
right = Right.new
right.name = "Taskmaster"
right.description = "Gives the possessor the ability to view, create, manipulate and schedule jobs. Jobs run a fixed set of operations defined in the codebase; arbitrary scripts are not supported."
right.save
right = Right.new
right.name = "Detective"
right.description = "Gives the posessor the ability to create and manipulate stored searches and display filters."
right.save
role = Role.new
role.name = "Analyst"
role.description = "This is a very powerful role.  The possessor may see all events.  These users may also see and create searches, display filters, etc.  Users with this right may also create and schedule jobs."
role.rights << Right.find_by_name("Viewer")
role.rights << Right.find_by_name("Commentator")
role.rights << Right.find_by_name("Taskmaster")
role.rights << Right.find_by_name("Detective")
role.save
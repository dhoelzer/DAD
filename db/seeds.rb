# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rake db:seed (or created alongside the db with db:setup).
#
# Examples:
#
#   cities = City.create([{ name: 'Chicago' }, { name: 'Copenhagen' }])
#   Mayor.create(name: 'Emanuel', city: cities.first)
user=User.new
user.username="admin"
user.password="Password1"
user.attempts = 0
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
right.description = "Gives the possessor the ability to view, create, manipulate and schedule jobs.  Extremely powerful.  Can be used to compromise the system."
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
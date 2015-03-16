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
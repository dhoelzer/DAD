# Seed data for rake db:seed.
#
# Idempotent: every lookup is find_or_create_by and every join is guarded, so
# re-running -- which provision.sh does on every Vagrant provision -- leaves the
# same counts rather than duplicating every Role and Right. The previous version
# used bare new/save, so two runs produced 2 admin users, 4 roles and 10 rights
# where 1, 2 and 5 were intended.
#
# The admin password is NOT committed: it comes from DAD_ADMIN_PASSWORD, and
# seeding fails loudly if that is unset rather than silently creating a
# well-known "Password1" account on a public host.
admin_password = ENV["DAD_ADMIN_PASSWORD"]
raise "Refusing to seed: set DAD_ADMIN_PASSWORD to the initial admin password." if admin_password.nil? || admin_password.empty?

admin_user = ENV["DAD_ADMIN_USER"] || "admin"

seed_rights = {
  "Admin" => "This right grants complete and absolute access to everything.  This should only ever be assigned to the Administrators role.",
  "Viewer" => "Gives the possessor the ability to view events and alerts",
  "Commentator" => "Gives the possessor the ability to comment on alerts",
  "Taskmaster" => "Gives the possessor the ability to view, create, manipulate and schedule jobs. Jobs run a fixed set of operations defined in the codebase; arbitrary scripts are not supported.",
  "Detective" => "Gives the posessor the ability to create and manipulate stored searches and display filters."
}

seed_roles = {
  "Administrators" => ["Admin"],
  "Analyst" => %w[Viewer Commentator Taskmaster Detective]
}

seed_rights.each { |name, description| Right.find_or_create_by!(name: name) { |r| r.description = description } }

# Role#rights is a has_and_belongs_to_many through rights_roles, which has no
# unique index, so << appends a duplicate pair on every run. The include? guard
# keeps the join table clean.
seed_roles.each do |name, right_names|
  role = Role.find_or_create_by!(name: name) do |r|
    r.description = name == "Administrators" ?
      "This role has only one right, 'Admin'.  This grants complete access to absolutely everything.  Nothing is hidden from your sight.  Only one or two users should ever have this role!!" :
      "This is a very powerful role. The possessor may see all events. These users may also see and create searches, display filters, etc. Users with this right may also create and schedule jobs."
  end
  right_names.each do |rn|
    right = Right.find_by!(name: rn)
    role.rights << right unless role.rights.include?(right)
  end
end

# Created once. Deliberately not updated on later runs: an operator who changed
# the admin password must not have it reset by a re-provision, so a password
# change is not undone here.
if User.find_by(username: admin_user).nil?
  user = User.create!(username: admin_user, attempts: 0)
  user.store_password(admin_password)
  user.save!
  admins = Role.find_by!(name: "Administrators")
  user.roles << admins unless user.roles.include?(admins)
  user.save!
end

# Partition maintenance, Postgres only.
#
# events and events_words are range-partitioned by month (migration
# 20261016000001), and that only pays for itself if someone creates the coming
# months and drops the expired ones. Without this Job, ingestion eventually hits
# months with no partition and retention never happens.
#
# Seeded rather than left to an operator because forgetting it is silent: the
# DEFAULT partition quietly absorbs the strays.
#
# Once a day is plenty -- the horizon is two months wide, so a day or two of
# missed runs costs nothing. Retention length comes from DAD_EVENT_RETENTION_DAYS
# (default 365), not from here.
if EventPartitioning.supported?
  admin = User.find_by(username: admin_user)
  unless admin.nil? || Job.exists?(script: 'maintain_event_partitions')
    Job.create!(
      name: 'Maintain event partitions',
      description: 'Creates next month\'s event partitions and drops months older ' \
                   'than DAD_EVENT_RETENTION_DAYS. Postgres only.',
      user: admin,
      script: 'maintain_event_partitions',
      frequency: 86_400,
      next_run: Time.now,
      last_run: nil
    )
  end
end

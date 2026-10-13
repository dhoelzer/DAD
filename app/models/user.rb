# An operator account: credentials plus the roles that grant rights.
#
# Authentication is handled by UsersController#do_logon; authorisation everywhere
# else flows through has_right?, which every controller's authorized? calls.
class User < ActiveRecord::Base
  has_and_belongs_to_many :roles
  has_many :comments
  has_many :exclusions
  has_many :jobs
  has_many :rights, through: :roles
  has_one :session

  # Hashes +password+ with a per-user salt and stores it as "salt$hexdigest".
  #
  # Call this instead of assigning #password directly when creating or updating a
  # user (UsersController#create/#update do). Note the scheme is a single fast
  # SHA-256 round with a 4-digit salt -- not suitable against offline cracking;
  # see RECOMMENDATIONS.md 1.3.
  def store_password(password)
    salt = Random.srand % 9999
    hash = Digest::SHA256.hexdigest "#{salt}#{password}"
    self.password = "#{salt}$#{hash}"
  end

  # True if +password+ matches the stored "salt$hexdigest" value.
  #
  # Returns false rather than raising when #password is nil or malformed. The
  # comparison is a plain string equality, so it is not constant-time.
  def check_password(password)
    salt,hash = self.password.split('$')
    calculated_hash = Digest::SHA256.hexdigest "#{salt}#{password}"
    return true if calculated_hash == hash
    return false
  end

  # Clears the failed-logon counter in memory (call #save to persist).
  # Used by the lockout logic in UsersController#do_logon.
  def zero_attempts
    self.attempts = 0
  end

  # Show the "Users" tab only to users holding the Admin right.
  def self.hidden?(current_user = nil)
    return true if current_user.nil?
    return true unless current_user.has_right?("Admin")
    return false
  end

  # Roles this user does not yet hold -- candidate list for the grant form.
  def ungranted_roles
    return Role.all - self.roles
  end

  # True if this user effectively holds +right+.
  #
  # +right+ is a right *name* (String). Anyone holding the Admin right returns
  # true for every right, so Admin is a wildcard and does not need to be granted
  # each permission individually. Returns false for an unknown right name.
  def has_right?(right)
    right = Right.where(:name => right).first
    admin = Right.where(:name => "Admin").first
    return true if self.rights.include?(admin) # Always return true for the administrator role regardless of rights
    self.rights.include?(right)
  end

  # True if +role+ (a Role record) is assigned to this user.
  def has_role?(role)
    self.roles.include?(role)
  end
end

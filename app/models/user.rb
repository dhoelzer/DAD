# An operator account: credentials plus the roles that grant rights.
#
# Authentication is handled by UsersController#do_logon; authorisation everywhere
# else flows through has_right?, which every controller's authorized? calls.
class User < ActiveRecord::Base
  # The right that satisfies every authorisation check.
  ADMIN_RIGHT = 'Admin'

  has_and_belongs_to_many :roles
  has_many :comments
  has_many :exclusions
  has_many :jobs
  has_many :rights, through: :roles
  has_one :session

  BCRYPT_COST = 12

  # Hashes +password+ with bcrypt and stores the self-describing hash.
  #
  # Call this instead of assigning #password directly (UsersController#create
  # and #update do). bcrypt is a slow, salted, adaptive KDF; the stored value
  # embeds the algorithm version, cost factor and salt, so #check_password needs
  # no separate salt column.
  #
  # Returns the hash as well as assigning it, so callers can use the return
  # value without re-reading the attribute.
  def store_password(password)
    # bcrypt silently truncates at 72 bytes; reject rather than accept a
    # password whose tail is ignored.
    raise ArgumentError, "password is too long" if password.nil? || password.bytesize > 72
    self.password = BCrypt::Password.create(password, cost: BCRYPT_COST)
  end

  # True if +password+ matches the stored hash.
  #
  # Transparently handles the pre-bcrypt "salt$sha256hex" format: a legacy row
  # is verified with the old scheme and, on success, re-hashed with bcrypt and
  # saved. So existing accounts keep working and are upgraded on next login
  # without a mass reset. Returns false for a nil or malformed stored value
  # rather than raising.
  def check_password(password)
    return false if self.password.blank? || password.nil?
    if legacy_hash?
      return false unless legacy_match?(password)
      store_password(password)
      save!
      return true
    end
    begin
      BCrypt::Password.new(self.password) == password
    rescue BCrypt::Errors::InvalidHash
      false
    end
  end

  # True if #password holds the pre-bcrypt "salt$sha256hex" format.
  def legacy_hash?
    self.password.to_s =~ /\A\d{1,5}\$[0-9a-f]{64}\z/ ? true : false
  end

  # Verifies +password+ against a legacy "salt$sha256hex" value.
  #
  # Kept only so existing accounts can be upgraded on login; it is deliberately
  # not usable for new passwords. The old scheme used `Random.srand % 9999`,
  # which seeds the global PRNG and returns the previous seed, so the salt space
  # is ~10k predictable values -- treat any un-upgraded hash as compromised.
  def legacy_match?(password)
    salt, hash = self.password.split('$')
    return false if salt.nil? || hash.nil?
    calculated = Digest::SHA256.hexdigest "#{salt}#{password}"
    # Constant-time comparison; the old code used ==.
    ActiveSupport::SecurityUtils.secure_compare(calculated, hash)
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
  # True when the user holds +right+ (a Right row or its name), or holds Admin,
  # which satisfies everything.
  #
  # Resolved against the user's own right names rather than by looking up the
  # requested right and Admin separately: that was two Right queries on every
  # call, and authorized? calls it once per required right per request.
  def has_right?(right)
    names = right_names
    return true if names.include?(ADMIN_RIGHT)
    names.include?(right.is_a?(Right) ? right.name : right.to_s)
  end

  # Memoised per instance. Safe because the callers only read authorisation;
  # the paths that grant or revoke rights act on Role records and take effect
  # for the next request's user.
  def right_names
    @right_names ||= rights.pluck(:name)
  end

  # True if +role+ (a Role record) is assigned to this user.
  def has_role?(role)
    self.roles.include?(role)
  end
end

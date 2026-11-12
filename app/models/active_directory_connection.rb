# An Active Directory domain DAD can query for the machines it should poll.
#
# This answers "which Windows hosts exist?" from the directory rather than from
# an operator maintaining the list by hand. The import flow is preview-then-apply:
# query, show what is not already a target, let the operator uncheck some, then
# create the rest. See AdImportBatch for why the preview is persisted.
#
# Two distinct credentials live here, and they are not interchangeable:
#
#   password    binds to the directory. Read access to computer objects; in a
#               real domain that is a low-privilege account, but it is still a
#               domain credential and it is encrypted at rest for that reason.
#   poll_password  the WinRM login applied to every host this connection
#               imports. Without it, an imported host is a target that cannot
#               poll, which is a feature that looks finished and is not.
#
# Nav bar: visible to Admin only. Unlike windows_targets, where reading the list
# is a Viewer action, the sensitive act here is the enumeration itself -- a query
# returns the entire machine inventory, which is reconnaissance-grade information
# about the network.
class ActiveDirectoryConnection < ActiveRecord::Base
  belongs_to :polling_priority
  has_many :ad_import_batches, dependent: :destroy

  def self.hidden?(current_user = nil)
    return true if current_user.nil?
    return true unless current_user.has_right?('Admin')
    false
  end

  # Builds the LDAP URI, so anything outside this set could point the bind at a
  # different scheme or host. Same reasoning as WindowsTarget::ADDRESS.
  HOST = /\A[A-Za-z0-9][A-Za-z0-9.\-_:]*\z/.freeze

  # A DN is a comma-separated list of RDN components. Deliberately permissive on
  # the inside: RFC 4514 allows parentheses unescaped in a value ("OU=Sales (EU)"),
  # and real DNs carry spaces, apostrophes and non-ASCII names, so tightening this
  # would reject working directories.
  #
  # This is a well-formedness check, not an injection guard. bind_dn and
  # search_base reach net-ldap as the discrete bind username and search base --
  # they are never interpolated into a filter string, so there is nothing here to
  # escape. The value that DOES go into a filter is the operator-supplied host
  # filter, and that is escaped in AdQuery.escape_value. Requiring a recognised
  # attribute type up front just turns "you pasted the wrong thing" into an error
  # at save time instead of a confusing bind failure at query time.
  DN = /\A\s*(CN|OU|DC|ST|L|O|C|UID|E)\s*=/i.freeze

  validates :name, presence: true, uniqueness: true
  validates :host, presence: true, format: { with: HOST }
  validates :port, presence: true,
                   inclusion: { in: [389, 636], message: 'must be 389 (StartTLS) or 636 (LDAPS)' }
  # Expressed as custom validators rather than `format: { with: DN }`. The check
  # is a prefix test, not a whole-value format: a DN is a comma-separated list of
  # RDNs and RFC 4514 allows spaces, apostrophes, parentheses and non-ASCII inside
  # the values, so a `\z`-anchored regex either rejects real DNs or has to parse
  # the escaping rules to be worth writing. `format:` implies the anchored reading
  # to both readers and Brakeman's ValidationRegex check, which is why this is not
  # written that way.
  validates :search_base, presence: true
  validate :bind_dn_is_well_formed
  validate :search_base_is_well_formed
  validates :event_logs, presence: true
  validate :event_logs_are_safe_channel_names

  # A bind needs both halves. Anonymous bind is refused rather than allowed: it
  # typically returns nothing useful, so an operator who left the credentials
  # blank would see "no new hosts" and reasonably conclude the domain was
  # already fully imported. A loud validation beats a plausible lie.
  validate :bind_credential_present

  # Both credentials are encrypted at rest. The columns hold ciphertext.
  encrypts :password
  encrypts :poll_password

  # Connections an import may use. Disabled means "configured but not in play",
  # matching WindowsTarget#disable! rather than deleting the row.
  def self.enabled
    where(enabled: true)
  end

  # True when the bind is over TLS on the standard LDAPS port.
  def ldaps?
    port == 636
  end

  # 389 is only acceptable if StartTLS is negotiated before the bind. The model
  # does not silently upgrade: it reports what will actually happen so the UI
  # can say it out loud.
  def plaintext_bind?
    port == 389
  end

  # The channels applied to imported hosts, as an Array in the order entered.
  def log_list
    event_logs.to_s.split(',').map(&:strip).reject(&:empty?)
  end

  def display_name
    return "(#{host})" if name.nil? || name.strip.empty?
    name
  end

  # The defaults an import applies, in the shape AdImporter consumes. Read here
  # rather than passed through the form: a credential must not travel through a
  # browser on the way back from the preview page.
  def import_defaults
    {
      polling_priority_id: polling_priority_id,
      event_logs: event_logs,
      username: poll_username,
      password: poll_password
    }
  end

  # A connection with no polling credential will create targets that cannot
  # authenticate over WinRM. Surfaced as a warning rather than a hard validation
  # because an operator may legitimately want to import the inventory first and
  # set the credential afterwards -- but the preview page has to say so, or the
  # result looks like a successful import of hosts that silently never poll.
  def polling_credential_present?
    poll_username.present? && poll_password.present?
  end

  private

  def bind_dn_is_well_formed
    return if bind_dn.blank?
    return if DN.match?(bind_dn)
    errors.add(:bind_dn, 'must be a distinguished name such as ' \
                         'CN=svc-dad,OU=Service Accounts,DC=corp,DC=example,DC=com')
  end

  def search_base_is_well_formed
    return if search_base.blank?
    return if DN.match?(search_base)
    errors.add(:search_base, 'must be a distinguished name such as ' \
                             'DC=corp,DC=example,DC=com')
  end

  def bind_credential_present
    errors.add(:bind_dn, 'is required to bind') if bind_dn.blank?
    return if password.present?
    errors.add(:password, 'is required: an anonymous bind cannot reliably read ' \
                          'computer objects, and would report zero new hosts')
  end

  # Copied reasoning from WindowsTarget: these strings end up in a wevtutil
  # command line executed on a remote host. An unvalidated channel name is
  # remote command execution on a machine DAD authenticates to with a domain
  # credential.
  def event_logs_are_safe_channel_names
    names = event_logs.to_s.split(',')
    if names.map(&:strip).reject(&:empty?).empty?
      errors.add(:event_logs, 'must name at least one event log')
      return
    end

    bad = names.map(&:strip).reject { |n| n.match?(WindowsTarget::LOG_NAME) }
    return if bad.empty?

    errors.add(:event_logs,
               "contains names that are not valid event log channels: #{bad.join(', ')}")
  end
end

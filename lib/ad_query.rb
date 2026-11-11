require 'json'

# Queries Active Directory for the computer objects it knows about.
#
# The LDAP call sits behind an injectable client rather than being inlined. Not
# for mockery: there is no domain controller in CI, so the parts that can
# actually be wrong -- filter construction, workstation/server classification,
# and the address matching that decides whether a host is already a target --
# have to be testable without one. Same shape as WindowsPoll::Transport.
#
# Three things here are load-bearing and none of them are obvious from the
# requirement:
#
#   Paging. Active Directory caps a single search at MaxPageSize, 1000 entries by
#     default. A domain with more machines than that returns a TRUNCATED list,
#     and truncation is silent -- the operator sees a plausible list and has no
#     way to know it is missing half the fleet. net-ldap negotiates RFC 2696
#     paged results itself, so the fix is to not defeat it: never pass a :size
#     limit, and count what came back.
#
#   Filter escaping. The host filter is operator-supplied text that goes into an
#     LDAP search filter. Unescaped, a value containing `*`, `(` or `)` changes
#     the structure of the filter -- `*)(objectClass=user` turns a computer
#     lookup into something else entirely. Escaped per RFC 4515 instead.
#
#   Unknown operating system. A machine joined to AD may be Linux, an appliance,
#     or a Windows install whose operatingSystem attribute is simply unset.
#     Neither workstation nor server, so it matches no filter. It is reported as
#     a count rather than silently dropped, because a filter that quietly omits
#     machines is exactly how an operator ends up believing the fleet is fully
#     covered when it is not.
module AdQuery
  # primaryGroupID for the built-in Domain Controllers group. A DC matches
  # "servers", and bulk-enabling WinRM polling against one is a decision worth
  # making deliberately rather than by accident, so the flag is surfaced and the
  # operator can uncheck it. 517 is the read-only DC group.
  DOMAIN_CONTROLLER_GROUP = 516
  READ_ONLY_DC_GROUP = 517

  # Attributes worth fetching. Requesting a named list rather than `*` keeps the
  # result set small on a large domain and avoids pulling attributes (security
  # descriptors, BLs) that are large and useless here.
  REQUESTED_ATTRIBUTES = %w[
    dNSHostName
    dnshostname
    name
    operatingSystem
    operatingSystemVersion
    primaryGroupID
    whenCreated
  ].freeze

  # One machine as AD described it.
  Entry = Struct.new(:address, :name, :operating_system, :host_class,
                     :domain_controller, :ad_created_at, keyword_init: true)

  class << self
    # Runs the search and returns [entries, already_present_addresses].
    #
    # `client` is anything responding to #search_computers(filter, attributes);
    # the real one is LdapClient. Kept a parameter rather than a module-level
    # default so the seam is explicit at every call site.
    def run(connection, host_filter: 'all', client: nil, host_class: nil)
      client ||= LdapClient.new(connection)
      filter = build_filter(host_filter: host_filter, host_class: host_class)

      entries = client.search_computers(filter, REQUESTED_ATTRIBUTES).map do |raw|
        to_entry(raw)
      end

      # AD returns computer objects for machines that have never registered a DNS
      # name (a stale or never-domain-joined record). dNSHostName is what WinRM
      # needs to connect, so a host without one cannot become a target.
      unnamed = entries.reject { |e| e.address.present? }
      usable  = entries.select { |e| e.address.present? }

      present = already_present(usable.map(&:address))

      [usable, present, unnamed.size]
    end

    # The LDAP search filter.
    #
    # host_class narrows on the OS string rather than on any AD attribute,
    # because AD has no "is this a server" flag. operatingSystem is the only
    # thing that distinguishes them, and it is free text -- see classify.
    def build_filter(host_filter: 'all', host_class: nil, name_contains: nil)
      parts = ['(objectClass=computer)']

      case host_filter.to_s
      when 'workstations'
        parts << '(!(operatingSystem=*Server*))'
        parts << '(operatingSystem=Windows*)'
      when 'servers'
        parts << '(operatingSystem=*Server*)'
      when 'all', ''
        # no OS constraint
      else
        raise ArgumentError, "unknown host filter: #{host_filter.inspect}"
      end

      if name_contains.present?
        parts << "(name=#{escape_value(name_contains)}*)"
      end

      parts.size == 1 ? parts.first : "(&#{parts.join})"
    end

    # RFC 4515 escaping. `* ( ) \` are filter syntax and NUL is a protocol
    # delimiter; all must be backslash-escaped or they alter the filter's
    # structure instead of being matched literally.
    def escape_value(value)
      # NUL is handled separately and must NOT be in the first class: escaping
      # it there yields backslash+NUL, and the NUL byte is still a protocol
      # delimiter. It has to become the hex pair \00.
      #
      # '\\00' with a doubled backslash, not '\00': Ruby processes octal escapes
      # even inside single quotes, so '\00' is a NUL byte -- which would put the
      # delimiter back into the filter while looking like it had been escaped.
      escaped = value.to_s.gsub(/[\\*()]/) { |c| "\\#{c}" }
      # Block form, deliberately. With a string replacement, gsub re-reads the
      # replacement and treats \0 as a backreference to the match -- which is
      # the NUL itself -- so the delimiter goes straight back into the filter.
      escaped.gsub("\u0000") { "\\00" }
    end

    # Classifies from the free-text operatingSystem attribute.
    #
    # Returns :server, :workstation, or :unknown. :unknown is not a guess that
    # failed -- it is a real category, and it is what keeps a Linux box joined to
    # AD, or an appliance, from being imported as a Windows host that can never
    # poll successfully.
    #
    # AD's own strings are examples, not a contract:
    #   "Microsoft Windows Server 2019 Standard"  -> :server
    #   "Microsoft Windows 10 Pro"               -> :workstation
    #   "Microsoft Windows 11 Enterprise"        -> :workstation
    #   "Windows 10 Pro for Workstations"        -> :workstation
    #   nil (Linux join, appliance, unset)       -> :unknown
    #
    # "Server" is checked first and wins: a SKU naming both is a server.
    def classify(operating_system)
      os = operating_system.to_s.strip
      return :unknown if os.empty?
      return :server if os.match?(/server/i)
      return :workstation if os.match?(/\bwindows\b/i)
      :unknown
    end

    # The address forms that identify the same machine.
    #
    # AD hands back dNSHostName as a fully qualified name --
    # "web01.corp.example.com" -- while an operator adding a host by hand types
    # "web01". Matching those as different strings produces two targets for one
    # machine, which double-polls it and interleaves two independent offset
    # states. So a target counts as present if it matches the FQDN or its first
    # DNS label, case-insensitively.
    def host_aliases(address)
      a = address.to_s.strip.downcase
      return [] if a.empty?
      short = a.split('.').first
      short.nil? || short.empty? ? [a] : [a, short].uniq
    end

    # Addresses of existing targets, matched on either alias form.
    def already_present(addresses)
      wanted = addresses.flat_map { |a| host_aliases(a) }.uniq
      return [] if wanted.empty?

      # LOWER() on both sides: Postgres = is case-sensitive, and AD returns
      # hostnames in whatever case the machine registered them. The array is
      # bound as a parameter list, so this stays parameterized.
      WindowsTarget.where('LOWER(windows_targets.address) IN (?)', wanted).pluck(:address)
    end

    private

    def to_entry(raw)
      os = fetch(raw, 'operatingSystem')
      address = fetch(raw, 'dNSHostName') || fetch(raw, 'dnshostname')

      Entry.new(
        address: address.to_s.strip.downcase.presence,
        name: fetch(raw, 'name'),
        operating_system: os,
        host_class: classify(os),
        domain_controller: domain_controller?(raw),
        ad_created_at: fetch(raw, 'whenCreated')
      )
    end

    # net-ldap keys attributes by the lowercased name the server sent, but the
    # casing AD replies with varies, so look up case-insensitively.
    def fetch(raw, key)
      value = raw[key] || raw[key.downcase]
      value.is_a?(Array) ? value.first : value
    end

    def domain_controller?(raw)
      gid = fetch(raw, 'primaryGroupID')
      gid.to_s == DOMAIN_CONTROLLER_GROUP.to_s || gid.to_s == READ_ONLY_DC_GROUP.to_s
    end
  end

  # The real LDAP client. Everything that touches the network lives here so the
  # rest of AdQuery can be tested without a domain controller.
  class LdapClient
    # AD's own page cap is 1000; net-ldap requests 126 per page and loops on the
    # RFC 2696 cookie. Both are below any MaxPageSize that matters, so paging is
    # automatic as long as no :size limit is passed.
    def initialize(connection, verify: nil)
      require 'net/ldap'
      @connection = connection
      # Default: verify the server certificate. WINDOWS_SSL_VERIFY=none is the
      # existing escape hatch for an internal CA, reused here rather than
      # inventing a second knob for the same decision.
      @verify = verify.nil? ? !AdQuery.insecure_tls? : verify
    end

    def search_computers(filter, attributes)
      ldap = build_ldap
      raise "bind to #{@connection.host} failed: #{ldap.get_operation_result.message}" unless bind(ldap)

      results = []
      ldap.search(base: @connection.search_base,
                  filter: filter,
                  attributes: attributes) do |entry|
        results << entry_to_hash(entry)
      end

      result = ldap.get_operation_result
      # A failed search must not look like an empty domain. This is the same
      # class of failure as reporting an access-denied event channel as "no
      # events": silence is indistinguishable from "nothing there".
      unless result.code.zero?
        raise "search under #{@connection.search_base} failed: #{result.message} (code #{result.code})"
      end

      results
    end

    private

    def build_ldap
      opts = {
        host: @connection.host,
        port: @connection.port,
        base: @connection.search_base
      }
      if @connection.ldaps?
        opts[:encryption] = { method: :simple_tls, tls_options: tls_options }
      else
        # 389 with StartTLS. The bind is not in the clear only if this is
        # negotiated, which is why the model reports plaintext_bind? and the UI
        # says so out loud.
        opts[:encryption] = { method: :start_tls, tls_options: tls_options }
      end
      Net::LDAP.new(opts)
    end

    def bind(ldap)
      ldap.bind(authentication: { method: :simple,
                                  username: @connection.bind_dn,
                                  password: @connection.password })
    end

    def tls_options
      { verify_mode: @verify ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE }
    end

    def entry_to_hash(entry)
      h = {}
      entry.attrs.each do |attr|
        h[attr] = entry[attr]
      end
      h
    end
  end

  # Reuses the existing Windows TLS opt-out rather than adding a second one.
  def self.insecure_tls?
    ENV['WINDOWS_SSL_VERIFY'].to_s.casecmp('none').zero?
  end
end

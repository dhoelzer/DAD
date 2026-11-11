# Importing Windows hosts from Active Directory.
#
# Two tables. active_directory_connections holds the directory to query and the
# defaults applied to whatever it returns; ad_import_batches holds one previewed
# candidate list that may or may not have been applied.
#
# The batch table is the load-bearing one, and it exists for a reason that is not
# obvious from the requirement. The flow is "query, show me what is new, let me
# uncheck some, then add them". The tempting implementation throws the candidate
# list away between the preview and the apply and re-derives it from the form.
# That is unsafe here specifically: a WindowsTarget row makes this server connect
# OUT to `address` carrying a domain credential. If the apply step trusted names
# submitted by the browser, a crafted POST would add any host the attacker named
# and hand it our credential -- SSRF with a domain login attached, through a form
# that looks like it only ever subtracts.
#
# So the candidate set is persisted at preview time, and the apply step may only
# remove entries from it. A name that was never offered cannot be added, whatever
# is posted. The audit trail (who previewed what, what was actually added) is a
# bonus, not the reason.
#
# Credentials are encrypted at rest, as with windows_targets: a bind account that
# can read the whole directory is a domain credential, and in the clear it would
# sit in every pg_dump, backup and replica.
class CreateActiveDirectoryImport < ActiveRecord::Migration[8.1]
  def change
    create_table :active_directory_connections do |t|
      t.string :name, null: false

      # Host or domain to bind to. Validated rather than escaped: it builds the
      # LDAP(S) URI, same reasoning as WindowsTarget::ADDRESS.
      t.string :host, null: false

      # 636 = LDAPS. 389 is allowed but starts in plaintext and is only safe
      # after StartTLS is negotiated; the model refuses 389 unless the operator
      # has explicitly opted into that.
      t.integer :port, null: false, default: 636

      # Distinguished name to bind as, e.g. CN=svc-dad,OU=Service,DC=corp,DC=example,DC=com
      t.string :bind_dn

      # Bind credential. Ciphertext in the column, as with windows_targets.password.
      t.text :password

      # Search base for computer objects, e.g. DC=corp,DC=example,DC=com
      t.string :search_base, null: false

      # Applied to every host this connection imports, so an imported host is
      # pollable the moment it exists. Without these, "add them for polling"
      # would create rows that cannot poll -- a feature that looks finished and
      # is not. One shared polling account across the fleet is the normal setup;
      # per-host overrides remain available on the target itself.
      t.references :polling_priority, null: false, foreign_key: true
      t.string :poll_username
      t.text :poll_password
      t.text :event_logs, null: false, default: 'Application,System,Setup,ForwardedEvents'

      t.boolean :enabled, null: false, default: true

      t.datetime :last_query_at
      t.string :last_status

      t.timestamps
    end

    add_index :active_directory_connections, :name, unique: true

    create_table :ad_import_batches do |t|
      t.references :active_directory_connection, null: false, foreign_key: true
      # The user who ran the query, not the one who applied it. Both matter: the
      # person who chose the filter is not always the person who clicked import.
      t.references :user, foreign_key: true

      t.string :host_filter, null: false

      # Serialized candidate list: address, name, os, class, is_domain_controller,
      # and whether it was already present. Written server-side at preview time
      # and never accepted from a form, which is the point -- see the note above.
      # JSON rather than YAML because YAML.load on a blob that ever round-trips
      # through storage is a deserialization footgun, and these are flat scalars
      # that need no richer type.
      t.text :candidates, null: false

      t.datetime :applied_at
      t.integer :added_count

      t.timestamps
    end

    # The list an operator browses is "batches, newest first".
    add_index :ad_import_batches, [:active_directory_connection_id, :created_at]
  end
end

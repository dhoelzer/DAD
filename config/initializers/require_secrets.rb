# Fail closed in production if secrets are missing.
#
# Rails 4.2 only emits a deprecation warning when secret_key_base is blank, so
# an unconfigured host would boot and sign cookies with no key rather than
# refusing to start. Raising here turns a silent misconfiguration into a boot
# failure. See config/secrets.yml and provision.sh for how these are supplied.
if Rails.env.production?
  missing = []
  missing << "SECRET_KEY_BASE" if Rails.application.secrets.secret_key_base.blank?
  # Either a full DATABASE_URL or the individual DAD_DB_* variables are
  # acceptable; a blank password could otherwise fall through to Postgres
  # trust authentication.
  if ENV["DATABASE_URL"].blank? && ENV["DAD_DB_PASSWORD"].blank?
    missing << "DATABASE_URL or DAD_DB_PASSWORD"
  end

  if missing.any?
    raise "Refusing to boot in production: missing #{missing.join(' and ')}. " \
          "See config/secrets.yml."
  end
end

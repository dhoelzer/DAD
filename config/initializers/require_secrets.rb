# Fail closed in production if secrets are missing.
#
# Rails only emits a deprecation warning when secret_key_base is blank, so an
# unconfigured host would boot and sign cookies with no key rather than refusing
# to start. Raising here turns a silent misconfiguration into a boot failure.
# Reads ENV directly rather than Rails.application.secrets, which Rails 7.1
# deprecates and 7.2 removes; production has no other source for this value.
# See config/secrets.yml and provision.sh for how it is supplied.
if Rails.env.production?
  missing = []
  missing << "SECRET_KEY_BASE" if ENV["SECRET_KEY_BASE"].blank?
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

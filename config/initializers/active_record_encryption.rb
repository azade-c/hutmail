# For development/test, use environment-based keys
# In production, use Rails credentials
if Rails.env.test? || Rails.env.development?
  ActiveRecord::Encryption.configure(
    primary_key: "test-primary-key-at-least-12-bytes",
    deterministic_key: "test-deterministic-key-12-bytes",
    key_derivation_salt: "test-key-derivation-salt-12bytes"
  )
end

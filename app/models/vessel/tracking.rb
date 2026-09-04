module Vessel::Tracking
  extend ActiveSupport::Concern

  TOKEN_LENGTH = 24

  # Letters and digits only, so the link survives being dictated over the VHF,
  # hand-copied off a screen or pasted into a mail client that would otherwise
  # chew on punctuation. The floor of 16 is what keeps it unguessable; the
  # ceiling only keeps the URL sane. config/routes.rb mirrors this pattern so a
  # malformed token is a 404 at the router, without touching the database.
  TOKEN_FORMAT = /\A[A-Za-z0-9]{16,64}\z/

  included do
    has_secure_token :track_token, length: TOKEN_LENGTH

    normalizes :track_token, with: ->(token) { token.strip }

    # An empty field reads as "give me a new link". That is the only way to
    # revoke one that leaked: the old URL stops answering the moment this saves.
    before_validation :assign_track_token, if: -> { track_token.blank? }

    validates :track_token, uniqueness: true, format: { with: TOKEN_FORMAT }
  end

  private
    def assign_track_token
      self.track_token = self.class.generate_unique_secure_token(length: TOKEN_LENGTH)
    end
end

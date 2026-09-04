require "active_support/core_ext/securerandom"

module Vessel::Tracking
  extend ActiveSupport::Concern

  SLUG_LENGTH = 24

  # Letters and digits only, so the link survives being dictated over the VHF,
  # hand-copied off a screen or pasted into a mail client that would otherwise
  # chew on punctuation. The floor of 16 keeps a slug nobody bothered to choose
  # unguessable; the ceiling only keeps the URL sane. config/routes.rb mirrors
  # this pattern, so a malformed slug is a 404 at the router without a query.
  SLUG_FORMAT = /\A[A-Za-z0-9]{16,64}\z/

  included do
    normalizes :track_slug, with: ->(slug) { slug.strip }

    # A blank field reads as "draw me a new one", which is what makes this the
    # revocation path: the old URL stops answering the moment this saves. It
    # also covers a brand new vessel, which starts out without a slug.
    before_validation :assign_track_slug, if: -> { track_slug.blank? }

    validates :track_slug, uniqueness: true, format: { with: SLUG_FORMAT }
  end

  private
    # base58 rather than plain alphanumerics: it leaves out 0, O, I and l, the
    # four characters nobody reads aloud without being asked to repeat.
    def assign_track_slug
      self.track_slug = SecureRandom.base58(SLUG_LENGTH)
    end
end

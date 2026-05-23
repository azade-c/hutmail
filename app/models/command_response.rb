class CommandResponse < ApplicationRecord
  SOURCES = %w[subject body].freeze
  STATUSES = %w[pending sent included error].freeze

  belongs_to :vessel
  belongs_to :bundle, optional: true

  validates :source, inclusion: { in: SOURCES }
  validates :command, presence: true
  validates :response_text, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :pending, -> { where(status: "pending") }
  scope :pending_for_bundle, -> { where(source: "body", status: "pending") }

  def deliver_later
    CommandResponse::DeliverJob.perform_later(self)
  end

  def deliver_now
    account = vessel.relay_account

    message = CommandResponseMailer.new.deliver_with_auth_fallback(account) do |auth_method|
      CommandResponseMailer.send_response(self, auth_method:)
    end

    update!(status: "sent", sent_at: Time.current)
    append_to_sent(account, message)
  rescue => e
    update!(status: "error", error_message: e.message)
    Rails.logger.error "CommandResponse##{id} delivery failed: #{e.class} #{e.message}"
  end

  private
    def append_to_sent(account, message)
      return unless message

      account.append_to_sent(message.message.to_s)
    rescue => e
      Rails.logger.warn "CommandResponse##{id} failed to append sent copy: #{e.class} #{e.message}"
    end
end

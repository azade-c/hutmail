module Vessel::Bundling
  extend ActiveSupport::Concern

  class_methods do
    def bundle_all_now
      find_each do |vessel|
        vessel.build_and_deliver_bundle
      rescue => e
        Rails.logger.error "Vessel##{vessel.id} bundle failed: #{e.message}"
      end
    end
  end

  def build_bundle
    pending = CollectedMessage.pending
      .joins(:mail_account)
      .where(mail_accounts: { vessel_id: id })
      .includes(:mail_account)
      .oldest_first

    return nil if pending.empty?

    included_msgs = []
    remaining_msgs = []
    consumed = 0

    pending.each do |msg|
      if consumed + msg.stripped_size <= message_budget
        included_msgs << msg
        consumed += msg.stripped_size
      else
        remaining_msgs << msg
      end
    end

    bundle = bundles.create!(status: "draft")
    bundle.compose!(included_msgs, remaining_msgs)
    bundle
  end

  def deliver_bundle(bundle)
    return unless bundle&.status == "draft"

    RelayMailer.send_bundle(bundle).deliver_now
    mark_bundle_sent(bundle)
  rescue => e
    bundle.update!(status: "error", error_message: e.message)
    Rails.logger.error "Bundle##{bundle.id} delivery failed: #{e.message}"
  end

  def build_and_deliver_bundle
    if (bundle = build_bundle)
      deliver_bundle(bundle)
    end
    bundle
  end

  def build_and_deliver_get_response(messages)
    remaining = CollectedMessage.pending
      .joins(:mail_account)
      .where(mail_accounts: { vessel_id: id })
      .where.not(id: messages.pluck(:id))
      .oldest_first

    bundle = bundles.create!(status: "draft")
    bundle.compose!(messages, remaining)

    RelayMailer.send_bundle(bundle).deliver_now
    mark_bundle_sent(bundle)
    bundle
  rescue => e
    bundle&.update!(status: "error", error_message: e.message)
    raise
  end

  private
    def mark_bundle_sent(bundle)
      now = Time.current
      bundle.update!(status: "sent", sent_at: now)
      bundle.collected_messages.update_all(status: "sent", sent_at: now)
      mark_imap_read(bundle.collected_messages.includes(:mail_account))
    end

    def mark_imap_read(messages)
      messages.group_by(&:mail_account).each do |account, msgs|
        account.mark_as_read(msgs.map(&:imap_uid))
      rescue => e
        Rails.logger.warn "Failed to mark IMAP read for MailAccount##{account.id}: #{e.message}"
      end
    end
end

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

  def preview_bundle
    pending = pending_messages
    return nil if pending.empty?

    included, remaining = split_by_budget(pending)
    bundle = bundles.build(status: "preview")
    bundle.compose_text(included, remaining)
    bundle
  end

  def build_bundle
    pending = pending_messages
    return nil if pending.empty?

    included, remaining = split_by_budget(pending)
    bundle = bundles.create!(status: "draft")
    bundle.compose!(included, remaining)
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
    def pending_messages
      CollectedMessage.pending
        .joins(:mail_account)
        .where(mail_accounts: { vessel_id: id })
        .includes(:mail_account)
        .oldest_first
    end

    def split_by_budget(messages)
      included = []
      remaining = []
      consumed = 0

      messages.each do |msg|
        if consumed + msg.stripped_size <= message_budget
          included << msg
          consumed += msg.stripped_size
        else
          remaining << msg
        end
      end

      [ included, remaining ]
    end

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

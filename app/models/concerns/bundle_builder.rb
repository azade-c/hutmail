class BundleBuilder
  attr_reader :user, :bundle

  def initialize(user)
    @user = user
  end

  def build
    pending = user.mail_accounts
      .includes(:collected_messages)
      .flat_map { |ma| ma.collected_messages.pending.oldest_first }

    return nil if pending.empty?

    message_budget = user.message_budget
    included = []
    remaining = []
    consumed = 0

    pending.each do |msg|
      if consumed + msg.stripped_size <= message_budget
        included << msg
        consumed += msg.stripped_size
      else
        remaining << msg
      end
    end

    screener_budget = user.screener_budget
    screener_text = BundleFormatter.format_screener(remaining, screener_budget)

    @bundle = user.bundles.create!(
      status: "draft",
      total_raw_size: included.sum(&:raw_size),
      total_stripped_size: included.sum(&:stripped_size),
      bundle_text: BundleFormatter.format(included, remaining, screener_text, user),
      messages_count: included.size,
      remaining_count: remaining.size
    )

    included.each do |msg|
      msg.update!(bundle: @bundle)
    end

    @bundle
  end

  def deliver
    return unless bundle&.status == "draft"

    RelayMailer.send_bundle(bundle).deliver_now
    mark_sent
  rescue => e
    bundle.update!(status: "error", error_message: e.message)
    Rails.logger.error "Bundle##{bundle.id} delivery failed: #{e.message}"
  end

  def build_and_deliver
    build
    deliver if bundle
    bundle
  end

  private

  def mark_sent
    now = Time.current
    bundle.update!(status: "sent", sent_at: now)
    bundle.collected_messages.each do |msg|
      msg.update!(status: "sent", sent_at: now)
    end

    mark_imap_read(bundle.collected_messages)
  end

  def mark_imap_read(messages)
    messages.group_by(&:mail_account).each do |account, msgs|
      account.mark_as_read(msgs.map(&:imap_uid))
    rescue => e
      Rails.logger.warn "Failed to mark IMAP read for MailAccount##{account.id}: #{e.message}"
    end
  end
end

class GetResponseBuilder
  attr_reader :user, :messages, :bundle

  def initialize(user, messages)
    @user = user
    @messages = messages
  end

  def build_and_deliver
    remaining = CollectedMessage.pending
      .joins(:mail_account)
      .where(mail_accounts: { user_id: user.id })
      .where.not(id: messages.pluck(:id))
      .oldest_first

    screener_text = BundleFormatter.format_screener(remaining, Float::INFINITY)

    @bundle = user.bundles.create!(
      status: "draft",
      total_raw_size: messages.sum(&:raw_size),
      total_stripped_size: messages.sum(&:stripped_size),
      bundle_text: BundleFormatter.format(messages, remaining, screener_text, user),
      messages_count: messages.size,
      remaining_count: remaining.size
    )

    messages.each { |msg| msg.update!(bundle: @bundle) }

    RelayMailer.send_bundle(@bundle).deliver_now
    mark_sent
    @bundle
  rescue => e
    @bundle&.update!(status: "error", error_message: e.message)
    raise
  end

  private

  def mark_sent
    now = Time.current
    @bundle.update!(status: "sent", sent_at: now)
    messages.each { |msg| msg.update!(status: "sent", sent_at: now) }
  end
end

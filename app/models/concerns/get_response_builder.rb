class GetResponseBuilder
  attr_reader :vessel, :messages, :bundle

  def initialize(vessel, messages)
    @vessel = vessel
    @messages = messages
  end

  def build_and_deliver
    remaining = CollectedMessage.pending
      .joins(:mail_account)
      .where(mail_accounts: { vessel_id: vessel.id })
      .where.not(id: messages.pluck(:id))
      .oldest_first

    screener_text = BundleFormatter.format_screener(remaining, Float::INFINITY)

    @bundle = vessel.bundles.create!(
      status: "draft",
      total_raw_size: messages.sum(&:raw_size),
      total_stripped_size: messages.sum(&:stripped_size),
      bundle_text: BundleFormatter.format(messages, remaining, screener_text, vessel),
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

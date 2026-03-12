module Vessel::Dispatching
  extend ActiveSupport::Concern

  class_methods do
    def dispatch_all_now
      find_each do |vessel|
        vessel.dispatch_now
      rescue => e
        Rails.logger.error "Vessel##{vessel.id} dispatch failed: #{e.message}"
      end
    end
  end

  def dispatch_now
    bundle = compose_next_bundle
    bundle&.deliver!
    bundle
  end

  def preview_dispatch
    bundleable_messages = messages_to_bundle
    return nil if bundleable_messages.empty?

    included, remaining = split_by_budget(bundleable_messages)
    bundle = bundles.build(status: "preview")
    bundle.compose_text(included, remaining)
    bundle
  end

  def dispatch_get_response(messages)
    remaining = MessageDigest.bundleable
      .joins(:mail_account)
      .where(mail_accounts: { vessel_id: id })
      .where.not(id: messages.pluck(:id))
      .ordered

    bundle = bundles.create!(status: "draft")
    bundle.compose!(messages, remaining)
    bundle.deliver!
    bundle
  end

  private
    def messages_to_bundle
      MessageDigest.bundleable
        .joins(:mail_account)
        .where(mail_accounts: { vessel_id: id })
        .includes(:mail_account)
        .ordered
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

    def compose_next_bundle
      bundleable_messages = messages_to_bundle
      return nil if bundleable_messages.empty?

      included, remaining = split_by_budget(bundleable_messages)
      bundle = bundles.create!(status: "draft")
      bundle.compose!(included, remaining)
      bundle
    end
end

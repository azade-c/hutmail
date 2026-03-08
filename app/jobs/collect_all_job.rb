class CollectAllJob < ApplicationJob
  queue_as :default

  def perform
    Vessel.find_each do |vessel|
      vessel.mail_accounts.find_each do |account|
        account.collect_now
      rescue => e
        Rails.logger.error "CollectAllJob: MailAccount##{account.id} failed: #{e.message}"
      end
    end
  end
end

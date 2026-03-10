class CollectAllJob < ApplicationJob
  queue_as :default

  def perform
    MailAccount.collect_all_now
  end
end

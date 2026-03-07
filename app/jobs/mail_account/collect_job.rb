class MailAccount::CollectJob < ApplicationJob
  queue_as :default

  def perform(mail_account)
    mail_account.collect_now
  end
end

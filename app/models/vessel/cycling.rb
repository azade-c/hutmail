module Vessel::Cycling
  extend ActiveSupport::Concern

  class_methods do
    def cycle_all_now
      find_each do |vessel|
        vessel.run_cycle
      rescue => e
        Rails.logger.error "Vessel##{vessel.id} cycle failed: #{e.message}"
      end
    end
  end

  def run_cycle
    poll_relay_now
    collect_all_accounts
    dispatch_now
  end

  def collect_all_accounts
    mail_accounts.find_each do |account|
      account.collect_now
    rescue => e
      Rails.logger.error "Vessel##{id} MailAccount##{account.id} collect failed: #{e.message}"
    end
  end
end

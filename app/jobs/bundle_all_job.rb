class BundleAllJob < ApplicationJob
  queue_as :default

  def perform
    User.find_each do |user|
      builder = BundleBuilder.new(user)
      builder.build_and_deliver
    rescue => e
      Rails.logger.error "BundleAllJob: User##{user.id} failed: #{e.message}"
    end
  end
end

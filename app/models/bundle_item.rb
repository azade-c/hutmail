class BundleItem < ApplicationRecord
  belongs_to :bundle
  belongs_to :message_digest
end

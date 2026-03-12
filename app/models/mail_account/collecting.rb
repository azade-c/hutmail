module MailAccount::Collecting
  extend ActiveSupport::Concern

  included do
    after_create_commit :collect_later
  end

  class_methods do
    def collect_all_now
      joins(:vessel).find_each do |account|
        account.collect_now
      rescue => e
        Rails.logger.error "MailAccount##{account.id} collect failed: #{e.message}"
      end
    end
  end

  def collect_later
    MailAccount::CollectJob.perform_later(self)
  end

  def recollect!
    collect_now
  end

  def collect_now
    return 0 if vessel_paused?

    visible_message_ids = fetch_visible_message_ids

    if visible_message_ids
      reconcile_missing_messages(visible_message_ids)
      Rails.logger.info "MailAccount##{id} (#{short_code}): visible #{visible_message_ids.size} messages"
      visible_message_ids.size
    else
      0
    end
  end

  private
    def vessel_paused? = false

    def fetch_visible_message_ids
      visible_message_ids = []

      with_imap_connection do |imap|
        imap.select("INBOX")

        collection_uids(imap).each do |uid|
          envelope = imap.fetch(uid, [ "ENVELOPE", "BODY.PEEK[]", "RFC822.SIZE" ])&.first
          next unless envelope

          message_id = extract_message_id(envelope)
          next if message_id.blank?

          existing = message_digests.find_by(imap_message_id: message_id)
          if existing
            visible_message_ids << message_id
            refresh_existing_message(existing, uid)
          else
            collect_message(envelope, uid, visible_message_ids)
          end
        end
      end

      visible_message_ids
    rescue Net::IMAP::Error, SocketError, Errno::ECONNREFUSED => e
      Rails.logger.error "MailAccount##{id} IMAP error: #{e.message}"
      nil
    end

    def collection_uids(imap)
      if skip_already_read
        imap.search([ "UNSEEN" ])
      else
        imap.search([ "ALL" ])
      end
    end

    def collect_message(envelope, uid, visible_message_ids)
      raw = envelope.attr["BODY[]"]
      raw_size = envelope.attr["RFC822.SIZE"] || raw&.bytesize || 0
      mail = Mail.new(raw)
      return if from_relay_address?(mail)

      stripped = MessageDigest.strip_mail(mail)
      attachments_metadata = extract_attachments_metadata(mail)

      message_digests.create!(
        imap_uid: uid,
        imap_message_id: extract_message_id(envelope),
        from_address: mail.from&.first,
        from_name: extract_display_name(mail),
        to_address: mail.to&.join(", "),
        subject: mail.subject,
        date: mail.date || Time.current,
        raw_size: raw_size,
        stripped_body: stripped,
        stripped_size: stripped.bytesize,
        status: :collected,
        collected_at: Time.current,
        attachments_metadata: attachments_metadata,
      )

      visible_message_ids << extract_message_id(envelope)
    end

    def refresh_existing_message(message, uid)
      attributes = { imap_uid: uid, collected_at: Time.current }

      if message.bundled?
        attributes[:status] = :requeued
      elsif message.no_longer_collectable?
        attributes[:status] = :collected
      end

      message.update!(attributes)
    end

    def reconcile_missing_messages(visible_message_ids)
      missing_messages = message_digests.where.not(imap_message_id: visible_message_ids)
      missing_messages.collected.update_all(status: MessageDigest.statuses.fetch("no_longer_collectable"))
      missing_messages.requeued.update_all(status: MessageDigest.statuses.fetch("bundled"))
    end

    def from_relay_address?(mail)
      sailmail = vessel.sailmail_address

      if sailmail.blank?
        false
      else
        mail.from&.any? { |from_address| from_address.casecmp?(sailmail) }
      end
    end

    def extract_message_id(fetch_data)
      fetch_data.attr["ENVELOPE"]&.message_id
    end

    def extract_display_name(mail)
      if mail[:from]&.display_names&.first.present?
        mail[:from].display_names.first
      end
    end

    def extract_attachments_metadata(mail)
      return nil unless mail.attachments.any?

      mail.attachments.map do |att|
        {
          name: att.filename,
          size: att.body.decoded.bytesize,
          content_type: att.content_type.split(";").first,
          inline: attachment_inline?(att)
        }
      end
    end

    def attachment_inline?(attachment)
      attachment.inline? || attachment.content_disposition&.include?("inline") || attachment.content_id.present?
    end
end

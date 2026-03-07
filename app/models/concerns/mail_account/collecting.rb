module MailAccount::Collecting
  extend ActiveSupport::Concern

  included do
    after_create_commit :collect_later
  end

  def collect_later
    MailAccount::CollectJob.perform_later(self)
  end

  def collect_now
    return if user_paused?

    messages = fetch_from_imap
    Rails.logger.info "MailAccount##{id} (#{short_code}): fetched #{messages.size} new messages"
    messages.size
  end

  private

  def user_paused?
    # TODO: AC 07mar26 implement PAUSE/RESUME state on user
    false
  end

  def fetch_from_imap
    collected = []

    with_imap_connection do |imap|
      imap.select("INBOX")

      uids = if skip_already_read
        imap.search([ "UNSEEN" ])
      else
        imap.search([ "ALL" ])
      end

      uids.each do |uid|
        envelope = imap.fetch(uid, [ "ENVELOPE", "RFC822", "RFC822.SIZE" ])&.first
        next unless envelope

        message_id = extract_message_id(envelope)
        next if message_id.blank?
        next if collected_messages.exists?(imap_message_id: message_id)

        raw = envelope.attr["RFC822"]
        raw_size = envelope.attr["RFC822.SIZE"] || raw&.bytesize || 0
        mail = Mail.new(raw)

        stripped = MessageStripper.strip(mail)
        attachments_meta = extract_attachments_metadata(mail)

        hutmail_id = HutmailIdGenerator.generate(
          mail_account: self,
          date: mail.date&.to_date || Date.current
        )

        msg = collected_messages.create!(
          hutmail_id: hutmail_id,
          imap_uid: uid,
          imap_message_id: message_id,
          from_address: mail.from&.first,
          from_name: extract_display_name(mail),
          to_address: mail.to&.join(", "),
          subject: mail.subject,
          date: mail.date || Time.current,
          raw_size: raw_size,
          stripped_body: stripped,
          stripped_size: stripped.bytesize,
          status: "pending",
          collected_at: Time.current,
          attachments_metadata: attachments_meta
        )

        collected << msg
      end
    end

    collected
  rescue Net::IMAP::Error, SocketError, Errno::ECONNREFUSED => e
    Rails.logger.error "MailAccount##{id} IMAP error: #{e.message}"
    []
  end

  def with_imap_connection
    imap = Net::IMAP.new(imap_server, port: imap_port, ssl: imap_use_ssl)
    imap.login(imap_username, imap_password)
    yield imap
  ensure
    imap&.logout rescue nil
    imap&.disconnect rescue nil
  end

  def extract_message_id(fetch_data)
    fetch_data.attr["ENVELOPE"]&.message_id
  end

  def extract_display_name(mail)
    if mail[:from]&.display_names&.first.present?
      mail[:from].display_names.first
    else
      nil
    end
  end

  def extract_attachments_metadata(mail)
    return nil unless mail.attachments.any?

    mail.attachments.map do |att|
      {
        name: att.filename,
        size: att.body.decoded.bytesize,
        content_type: att.content_type.split(";").first
      }
    end
  end
end

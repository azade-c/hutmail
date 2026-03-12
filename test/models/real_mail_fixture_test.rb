require "test_helper"

class RealMailFixtureTest < ActiveSupport::TestCase
  FIXTURE_DIRECTORY = Rails.root.join("test/fixtures/files/real_mail_corpus")
  REPLY_FIXTURE = "04_reply_message.eml"
  IMAGE_FIXTURE = "05_inline_image_message.eml"

  test "real reply email strips the previous French message block" do
    result = MessageDigest.strip_mail(mail_fixture(REPLY_FIXTURE))

    assert_equal expected_fixture("reply_message.expected.txt"), result
  end

  test "real inline image email keeps an embedded image placeholder" do
    result = MessageDigest.strip_mail(mail_fixture(IMAGE_FIXTURE))

    assert_equal expected_fixture("inline_image_message.expected.txt"), result
  end

  test "real mailbox fixtures compose the expected preview bundle" do
    preview = build_preview_bundle
    normalized_preview = normalize_preview_timestamp(preview.bundle_text)

    assert_equal expected_fixture("bundle_preview.expected.txt"), normalized_preview
  end

  private
    def build_preview_bundle
      vessel = Vessel.new(name: "Crew preview", sailmail_address: "CREW@sailmail.com")
      vessel.build_relay_account(
        imap_server: "imap.example.com",
        imap_port: 993,
        imap_encryption: "ssl",
        imap_username: "relay@example.com",
        imap_password: "secret",
        smtp_server: "smtp.example.com",
        smtp_port: 465,
        smtp_encryption: "ssl",
        smtp_username: "relay@example.com",
        smtp_password: "secret"
      )
      vessel.daily_budget_kb = 500
      vessel.bundle_ratio = 100
      vessel.save!

      account = vessel.mail_accounts.create!(
        name: "Crew",
        short_code: "CR",
        imap_server: "mail.example.test",
        imap_port: 993,
        imap_encryption: "ssl",
        imap_username: "crew@example.test",
        imap_password: "secret",
        smtp_server: "mail.example.test",
        smtp_port: 465,
        smtp_encryption: "ssl",
        smtp_username: "crew@example.test",
        smtp_password: "secret",
        skip_already_read: true
      )

      mail_fixture_paths.each_with_index do |path, index|
        create_message_from_fixture(account, path, index)
      end

      vessel.preview_dispatch
    end

    def create_message_from_fixture(account, path, index)
      raw = File.binread(path)
      mail = Mail.new(raw)
      stripped = MessageDigest.strip_mail(mail)

      account.message_digests.create!(
        imap_uid: index + 1,
        imap_message_id: mail.message_id || "msg-#{index}@example.test",
        from_address: mail.from&.first,
        from_name: mail[:from]&.display_names&.first,
        to_address: mail.to&.join(", "),
        subject: mail.subject,
        date: mail.date || Time.current,
        raw_size: raw.bytesize,
        stripped_body: stripped,
        stripped_size: stripped.bytesize,
        status: "pending",
        collected_at: Time.current,
        attachments_metadata: attachment_metadata(mail)
      )
    end

    def attachment_metadata(mail)
      mail.attachments.map do |attachment|
        {
          name: attachment.filename,
          size: attachment.body.decoded.bytesize,
          content_type: attachment.mime_type,
          inline: attachment.inline? || attachment.content_disposition&.include?("inline") || attachment.content_id.present?
        }
      end.presence
    end

    def mail_fixture_paths
      Dir[FIXTURE_DIRECTORY.join("*.eml")].sort
    end

    def mail_fixture(name)
      Mail.new(File.binread(FIXTURE_DIRECTORY.join(name)))
    end

    def expected_fixture(name)
      File.read(FIXTURE_DIRECTORY.join(name)).strip
    end

    def normalize_preview_timestamp(text)
      text.sub(/\A=== HUTMAIL .+ ===/, "=== HUTMAIL <timestamp> ===").strip
    end
end

require "test_helper"

class CollectedMessageStrippableTest < ActiveSupport::TestCase
  test "strips HTML to plain text" do
    mail = Mail.new do
      html_part do
        content_type "text/html"
        body "<h1>Hello</h1><p>World</p>"
      end
    end

    result = CollectedMessage.strip_mail(mail)
    assert_includes result, "Hello"
    assert_includes result, "World"
    assert_not_includes result, "<h1>"
  end

  test "prefers text part over html part" do
    mail = Mail.new do
      text_part do
        body "Plain text version"
      end
      html_part do
        content_type "text/html"
        body "<h1>HTML version</h1>"
      end
    end

    result = CollectedMessage.strip_mail(mail)
    assert_equal "Plain text version", result
  end

  test "removes mobile signatures" do
    mail = Mail.new do
      body "Real content\n\nSent from my iPhone"
    end
    mail.content_type = "text/plain"

    result = CollectedMessage.strip_mail(mail)
    assert_equal "Real content", result
  end

  test "removes French mobile signatures" do
    mail = Mail.new do
      body "Contenu réel\n\nEnvoyé de mon iPad"
    end
    mail.content_type = "text/plain"

    result = CollectedMessage.strip_mail(mail)
    assert_equal "Contenu réel", result
  end

  test "normalizes whitespace" do
    mail = Mail.new do
      body "Line 1\n\n\n\n\nLine 2"
    end
    mail.content_type = "text/plain"

    result = CollectedMessage.strip_mail(mail)
    assert_equal "Line 1\n\nLine 2", result
  end

  test "removes standalone URLs" do
    mail = Mail.new do
      body "Check this\nhttps://tracking.example.com/pixel\nReal content"
    end
    mail.content_type = "text/plain"

    result = CollectedMessage.strip_mail(mail)
    assert_not_includes result, "tracking.example.com"
    assert_includes result, "Real content"
  end

  test "handles empty body" do
    mail = Mail.new
    assert_equal "", CollectedMessage.strip_mail(mail)
  end
end

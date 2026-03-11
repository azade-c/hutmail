require "test_helper"

class CollectedMessage::StrippingTest < ActiveSupport::TestCase
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

  test "removes French reply block De/À/Objet/Date" do
    body = <<~TEXT
      Salut les gars !

      De : sailmailalibi@netcourrier.com
      À : famille cousin <alibi@francemel.fr>
      Objet : Sailmail montant 1
      Date : 01/03/2026 22:39:56 Europe/Paris

      Boris Cousin
    TEXT

    mail = Mail.new { body body }
    mail.content_type = "text/plain"

    result = CollectedMessage.strip_mail(mail)
    assert_includes result, "Salut les gars"
    assert_not_includes result, "sailmailalibi@netcourrier.com"
    assert_not_includes result, "Boris Cousin"
    assert_includes result, CollectedMessage::Stripping::PLACEHOLDER_QUOTED
  end

  test "removes French reply block with Envoyé and Cc" do
    body = <<~TEXT
      OK merci.

      De : alice@example.com
      Envoyé : lundi 2 mars 2026 10:00
      À : bob@example.com
      Cc : carol@example.com
      Objet : Re: Planning

      Voici le planning.
    TEXT

    mail = Mail.new { body body }
    mail.content_type = "text/plain"

    result = CollectedMessage.strip_mail(mail)
    assert_includes result, "OK merci"
    assert_not_includes result, "alice@example.com"
    assert_not_includes result, "Voici le planning"
    assert_includes result, CollectedMessage::Stripping::PLACEHOLDER_QUOTED
  end

  test "adds placeholder when quoted reply is removed" do
    body = "My reply\n\nOn 2026-03-01, Bob wrote:\n> Original message"

    mail = Mail.new { body body }
    mail.content_type = "text/plain"

    result = CollectedMessage.strip_mail(mail)
    assert_includes result, "My reply"
    assert_includes result, CollectedMessage::Stripping::PLACEHOLDER_QUOTED
  end

  test "adds image placeholder with filename and size" do
    mail = Mail.new do
      text_part { body "See attached photo" }
    end

    image_data = "x" * 2048
    mail.attachments.inline["sunset.jpg"] = { mime_type: "image/jpeg", content: image_data }

    result = CollectedMessage.strip_mail(mail)
    assert_includes result, "[image : sunset.jpg"
    assert_includes result, "2.0 KB"
    assert_includes result, "See attached photo"
  end
end

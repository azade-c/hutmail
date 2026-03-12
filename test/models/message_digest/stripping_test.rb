require "test_helper"

class MessageDigest::StrippingTest < ActiveSupport::TestCase
  test "strips HTML to plain text" do
    mail = Mail.new do
      html_part do
        content_type "text/html"
        body "<h1>Hello</h1><p>World</p>"
      end
    end

    result = MessageDigest.strip_mail(mail)
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

    result = MessageDigest.strip_mail(mail)
    assert_equal "Plain text version", result
  end

  test "removes mobile signatures" do
    mail = Mail.new do
      body "Real content\n\nSent from my iPhone"
    end
    mail.content_type = "text/plain"

    result = MessageDigest.strip_mail(mail)
    assert_equal "Real content", result
  end

  test "removes French mobile signatures" do
    mail = Mail.new do
      body "Contenu réel\n\nEnvoyé de mon iPad"
    end
    mail.content_type = "text/plain"

    result = MessageDigest.strip_mail(mail)
    assert_equal "Contenu réel", result
  end

  test "normalizes whitespace" do
    mail = Mail.new do
      body "Line 1\n\n\n\n\nLine 2"
    end
    mail.content_type = "text/plain"

    result = MessageDigest.strip_mail(mail)
    assert_equal "Line 1\n\nLine 2", result
  end

  test "removes standalone URLs" do
    mail = Mail.new do
      body "Check this\nhttps://tracking.example.com/pixel\nReal content"
    end
    mail.content_type = "text/plain"

    result = MessageDigest.strip_mail(mail)
    assert_not_includes result, "tracking.example.com"
    assert_includes result, "Real content"
  end

  test "handles empty body" do
    mail = Mail.new
    assert_equal "", MessageDigest.strip_mail(mail)
  end

  test "extracts body when content_type header is missing" do
    raw = "From: bob@test\nSubject: hi\n\nPlain body without content-type"
    mail = Mail.new(raw)

    result = MessageDigest.strip_mail(mail)
    assert_equal "Plain body without content-type", result
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

    result = MessageDigest.strip_mail(mail)
    assert_includes result, "Salut les gars"
    assert_not_includes result, "sailmailalibi@netcourrier.com"
    assert_not_includes result, "Boris Cousin"
    assert_includes result, MessageDigest::Stripping::PLACEHOLDER_QUOTED
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

    result = MessageDigest.strip_mail(mail)
    assert_includes result, "OK merci"
    assert_not_includes result, "alice@example.com"
    assert_not_includes result, "Voici le planning"
    assert_includes result, MessageDigest::Stripping::PLACEHOLDER_QUOTED
  end

  test "removes indented French reply block" do
    body = <<~TEXT
      Voici un test avec réponse

      et dessus des blocs

      Boris Cousin

        De : sailmailalibi@netcourrier.com
        À : famille cousin <alibi@francemel.fr>
        Objet : Sailmail montant 1
        Date : 01/03/2026 22:39:56 Europe/Paris

      Boris Cousin
    TEXT

    mail = Mail.new { body body }
    mail.content_type = "text/plain"

    result = MessageDigest.strip_mail(mail)
    assert_includes result, "Voici un test avec réponse"
    assert_includes result, "et dessus des blocs"
    assert_not_includes result, "sailmailalibi@netcourrier.com"
    assert_includes result, MessageDigest::Stripping::PLACEHOLDER_QUOTED
  end

  test "adds placeholder when quoted reply is removed" do
    body = "My reply\n\nOn 2026-03-01, Bob wrote:\n> Original message"

    mail = Mail.new { body body }
    mail.content_type = "text/plain"

    result = MessageDigest.strip_mail(mail)
    assert_includes result, "My reply"
    assert_includes result, MessageDigest::Stripping::PLACEHOLDER_QUOTED
  end

  test "adds image placeholder with filename and size" do
    mail = Mail.new do
      text_part { body "See attached photo" }
    end

    image_data = "x" * 2048
    mail.attachments.inline["sunset.jpg"] = { mime_type: "image/jpeg", content: image_data }

    result = MessageDigest.strip_mail(mail)
    assert_includes result, "[image : sunset.jpg"
    assert_includes result, "2.0 KB"
    assert_includes result, "See attached photo"
  end

  test "places inline image placeholder where html shows it" do
    raw = <<~MAIL
      MIME-Version: 1.0
      Content-Type: multipart/mixed; boundary="MIX"

      --MIX
      Content-Type: multipart/related; boundary="REL"

      --REL
      Content-Type: multipart/alternative; boundary="ALT"

      --ALT
      Content-Type: text/plain; charset="UTF-8"

      = ci-dessous une image dans le corps :

      Boris Cousin
      --ALT
      Content-Type: text/html; charset="UTF-8"

      <p>= ci-dessous une image dans le corps :</p><p><img src="cid:image1"></p><p>Boris Cousin</p>
      --ALT--
      --REL
      Content-Type: image/jpeg; name="IMG_4232_B-mini.jpg"
      Content-Disposition: inline; filename="IMG_4232_B-mini.jpg"
      Content-ID: <image1>
      Content-Transfer-Encoding: base64

      #{[ "x" * 2048 ].pack("m0")}
      --REL--
      --MIX
      Content-Type: image/jpeg; name="Balises.jpg"
      Content-Disposition: attachment; filename="Balises.jpg"
      Content-Transfer-Encoding: base64

      #{[ "y" * 1024 ].pack("m0")}
      --MIX--
    MAIL

    result = MessageDigest.strip_mail(Mail.new(raw))
    assert_equal <<~TEXT.strip, result
      = ci-dessous une image dans le corps :

      [image : IMG_4232_B-mini.jpg (2.0 KB)]

      Boris Cousin
    TEXT
    assert_not_includes result, "[image : Balises.jpg"
  end
end

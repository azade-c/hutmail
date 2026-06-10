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

  test "handles binary-encoded body without charset" do
    raw = <<~MAIL
      From: someone@example.com
      To: boris@example.com
      Subject: Test
      Content-Type: text/plain
      Content-Transfer-Encoding: 8bit

      Bonjour, voici des caract\xC3\xA8res accentu\xC3\xA9s.
    MAIL
    mail = Mail.new(raw.b)

    result = MessageDigest.strip_mail(mail)
    assert_equal Encoding::UTF_8, result.encoding
    assert_includes result, "caractères accentués"
  end

  test "handles invalid utf-8 bytes in body" do
    raw = "From: someone@example.com\r\nSubject: Test\r\n\r\nHello \xE9 world".b
    mail = Mail.new(raw)

    result = MessageDigest.strip_mail(mail)
    assert result.valid_encoding?
    assert_includes result, "Hello"
  end

  test "handles unconvertible charset like UTF-7 without raising" do
    raw = "From: someone@example.com\r\nSubject: Test\r\nContent-Type: text/plain; charset=UTF-7\r\n\r\nHello world".b
    mail = Mail.new(raw)

    result = MessageDigest.strip_mail(mail)
    assert result.valid_encoding?
    assert_includes result, "Hello world"
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

  test "keeps long body when a short header-like block has fewer than three headers" do
    intro = (1..30).map { |i| "Ligne d'intro numéro #{i} avec du contenu utile." }
    body = (intro + [ "", "De : capitaine@alibi.fr", "Objet : ravitaillement", "" ] +
      (1..500).map { |i| "Contenu important à transmettre, paragraphe #{i}." }).join("\n")

    mail = Mail.new { body body }
    mail.content_type = "text/plain"

    result = MessageDigest.strip_mail(mail)
    assert_includes result, "Ligne d'intro numéro 1"
    assert_includes result, "Contenu important à transmettre, paragraphe 500"
    assert_not_includes result, MessageDigest::Stripping::PLACEHOLDER_QUOTED
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
    mail.subject = "Re: Sailmail montant 1"

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
    mail.subject = "Re: Planning"

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
    mail.subject = "Re: Sailmail montant 1"

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
    mail.subject = "Re: Hello"

    result = MessageDigest.strip_mail(mail)
    assert_includes result, "My reply"
    assert_includes result, MessageDigest::Stripping::PLACEHOLDER_QUOTED
  end

  # ------------------------------------------------------------------
  # Reply detection: only genuine replies get their quotes trimmed
  # ------------------------------------------------------------------

  test "does not trim quoted text when the subject is not a reply" do
    body = "My new message\n\nDe : alice@example.com\nÀ : bob@example.com\nObjet : Planning\nDate : 02/03/2026\n\nLe contenu transféré à conserver."

    mail = Mail.new { body body }
    mail.content_type = "text/plain"
    mail.subject = "Voici une encyclique pour toi"

    result = MessageDigest.strip_mail(mail)
    assert_includes result, "My new message"
    assert_includes result, "Le contenu transféré à conserver"
    assert_includes result, "alice@example.com"
    assert_not_includes result, MessageDigest::Stripping::PLACEHOLDER_QUOTED
  end

  test "does not trim forwarded messages (Fwd / Tr prefixes)" do
    body = "Regarde ça\n\nDe : alice@example.com\nÀ : bob@example.com\nObjet : Doc\nDate : 02/03/2026\n\nMessage d'origine à transmettre."

    [ "Fwd: Doc", "Tr: Doc", "Fw: Doc" ].each do |subject|
      mail = Mail.new { body body }
      mail.content_type = "text/plain"
      mail.subject = subject

      result = MessageDigest.strip_mail(mail)
      assert_includes result, "Message d'origine à transmettre", "failed for subject #{subject.inspect}"
    end
  end

  test "keeps the full body of a non-reply newsletter with underscore separators" do
    # Regression: email_reply_parser/email_reply_trimmer treat a line of
    # underscores as a signature/delimiter and used to drop everything below
    # it. On a non-reply, nothing must be trimmed.
    body = <<~TEXT
      Table des matières
      Chapitre 1
      Chapitre 2

      ___________________________

      INTRODUCTION

      Le corps complet du message qui ne doit surtout pas être coupé.
      Il vient après la ligne de séparation en underscores.

      ------------------------------------------------------------------------

      Notes de bas de page à conserver aussi.
    TEXT

    mail = Mail.new { body body }
    mail.content_type = "text/plain"
    mail.subject = "Voici une encyclique pour toi"

    result = MessageDigest.strip_mail(mail)
    assert_includes result, "INTRODUCTION"
    assert_includes result, "Le corps complet du message qui ne doit surtout pas être coupé"
    assert_includes result, "Notes de bas de page à conserver aussi"
  end

  test "reply subject detection is multilingual and tolerant of casing and spacing" do
    %w[Re: RE: Ré: AW: R: Ri:].each do |prefix|
      assert MessageDigest.send(:reply_subject?, "#{prefix} Sujet"), "#{prefix} should be a reply"
    end
    assert MessageDigest.send(:reply_subject?, "RE : Sujet")
    assert MessageDigest.send(:reply_subject?, "re:sujet")

    [ "Rapport trimestriel", "Réunion demain", "Fwd: Doc", "Tr: Doc", "Bonjour" ].each do |subject|
      assert_not MessageDigest.send(:reply_subject?, subject), "#{subject.inspect} should not be a reply"
    end
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

  test "adds file placeholder for an inline non-image part" do
    raw = <<~MAIL
      MIME-Version: 1.0
      Content-Type: multipart/mixed; boundary="MIX"

      --MIX
      Content-Type: text/plain; charset="UTF-8"

      Voici le planning ci-joint.
      --MIX
      Content-Type: application/pdf; name="planning.pdf"
      Content-Disposition: inline; filename="planning.pdf"
      Content-Transfer-Encoding: base64

      #{[ "z" * 1024 ].pack("m0")}
      --MIX--
    MAIL

    result = MessageDigest.strip_mail(Mail.new(raw))
    assert_includes result, "[fichier : planning.pdf (1.0 KB)]"
    assert_includes result, "Voici le planning ci-joint."
  end
end

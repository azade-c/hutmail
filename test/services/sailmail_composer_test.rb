require "test_helper"

class SailmailComposerTest < ActiveSupport::TestCase
  Email = ImapFetcher::Email

  def make_account(name, username)
    Struct.new(:name, :imap_username).new(name, username)
  end

  def sample_emails
    [
      Email.new(uid: 1, from: "bob@example.com", to: "me@test.com", subject: "Re: Horta", date: Time.current, size: 820,
        body_preview: "Confirme rdv mardi au port",
        body_full: "Confirme rdv mardi au port de Horta.\nOn a hâte!\n\n-- \nBob\nSent from my iPhone",
        seen: true),
      Email.new(uid: 2, from: "Maman <maman@famille.fr>", to: "me@test.com", subject: "Nouvelles", date: 1.day.ago, size: 1230,
        body_preview: "Coucou mes chéris",
        body_full: "Coucou mes chéris, comment allez-vous ?\nBisous\n\n-- \nEnvoyé de mon iPad",
        seen: false),
    ]
  end

  def other_emails
    [
      Email.new(uid: 10, from: "banque@credit.fr", to: "pro@test.com", subject: "Relevé mensuel", date: 2.days.ago, size: 3174,
        body_preview: "Votre relevé de compte est disponible",
        body_full: "<html><body><p>Solde: 4521.30 EUR</p><p>Disclaimer: This email is confidential.</p></body></html>",
        seen: true),
    ]
  end

  test "bundle groups emails by account" do
    acct1 = make_account("Personal", "me@gmail.com")
    acct2 = make_account("Work", "pro@company.com")

    result = SailmailComposer.bundle({ acct1 => sample_emails, acct2 => other_emails })

    assert result[:text].include?("HUTMAIL")
    assert result[:text].include?("Personal (me@gmail.com)")
    assert result[:text].include?("Work (pro@company.com)")
    assert_equal 2, result[:accounts].size
    assert_equal 3, result[:message_count]
  end

  test "bundle assigns global indices across accounts" do
    acct1 = make_account("A", "a@test.com")
    acct2 = make_account("B", "b@test.com")

    result = SailmailComposer.bundle({ acct1 => sample_emails, acct2 => other_emails })

    assert result[:text].include?("#1 From: bob@example.com")
    assert result[:text].include?("#2 From: maman@famille.fr")
    assert result[:text].include?("#3 From: banque@credit.fr")
  end

  test "bundle strips signatures" do
    acct = make_account("Test", "me@test.com")
    result = SailmailComposer.bundle({ acct => sample_emails })

    refute result[:text].include?("Sent from my iPhone")
    refute result[:text].include?("Envoyé de mon iPad")
  end

  test "bundle strips HTML and disclaimers" do
    acct = make_account("Test", "me@test.com")
    result = SailmailComposer.bundle({ acct => other_emails })

    assert result[:text].include?("4521.30 EUR")
    refute result[:text].include?("<p>")
    refute result[:text].include?("Disclaimer")
  end

  test "bundle warns when over 35 KB" do
    acct = make_account("Big", "big@test.com")
    big_emails = (1..10).map do |i|
      Email.new(uid: i, from: "x@test.com", to: "me@test.com", subject: "Msg #{i}", date: Time.current,
        size: 5000, body_preview: "word " * 200, body_full: "word " * 1000, seen: false)
    end

    result = SailmailComposer.bundle({ acct => big_emails })
    assert result[:warnings].any? { |w| w.include?("35 KB") }
  end

  test "bundle skips empty accounts" do
    acct1 = make_account("Active", "a@test.com")
    acct2 = make_account("Empty", "b@test.com")

    result = SailmailComposer.bundle({ acct1 => sample_emails, acct2 => [] })

    assert result[:text].include?("Active")
    refute result[:text].include?("Empty")
    assert_equal 1, result[:accounts].size
  end

  test "bundle returns empty for no messages" do
    acct = make_account("Empty", "e@test.com")
    result = SailmailComposer.bundle({ acct => [] })

    assert result[:text].include?("no messages")
    assert_equal 0, result[:size]
  end

  test "strip_message removes quoted replies" do
    body = "Thanks!\n\nOn Mon, Jan 1, Bob wrote:\n> Original text"
    stripped = SailmailComposer.strip_message(body)

    assert stripped.include?("Thanks!")
    refute stripped.include?("Original text")
  end

  test "strip_message removes French quote patterns" do
    body = "Merci !\n\nLe 1 jan., Bob a écrit :\n> Message original"
    stripped = SailmailComposer.strip_message(body)

    assert stripped.include?("Merci")
    refute stripped.include?("Message original")
  end

  test "strip_message removes newsletter noise" do
    body = "Great content.\n\nUnsubscribe from this list\nhttps://tracking.example.com/pixel"
    stripped = SailmailComposer.strip_message(body)

    assert stripped.include?("Great content")
    refute stripped.include?("Unsubscribe")
  end
end

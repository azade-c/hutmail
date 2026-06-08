require "test_helper"

class VesselCommandingTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @vessel = vessels(:one)
  end

  # ------------------------------------------------------------------
  # Parsing & dispatch routing
  # ------------------------------------------------------------------

  test "ignores comments in commands" do
    text = "===CMD===\n# This is a comment\nSTATUS\n===END==="
    results = @vessel.parse_and_execute_commands(text)

    assert_equal 1, results.size
    assert_equal "STATUS", results.first[:command]
  end

  test "handles multiple commands in one body" do
    text = "===CMD===\nSTATUS\nPAUSE 3d\n===END==="
    results = @vessel.parse_and_execute_commands(text)

    assert_equal 2, results.size
  end

  test "unknown body command is reported and queues an error response" do
    text = "===CMD===\nDROP 01mar.GM.1\n===END==="
    assert_difference "@vessel.command_responses.count", 1 do
      @results = @vessel.parse_and_execute_commands(text)
    end

    assert_equal :unknown, @results.first[:status]
    cr = @vessel.command_responses.last
    assert_equal "body", cr.source
    assert_match(/unknown command/i, cr.response_text)
  end

  test "SEND with no message at all queues an error response for the sailor" do
    assert_difference "@vessel.command_responses.count", 1 do
      @results = @vessel.parse_and_execute_commands("===CMD===\nSEND.GM bob@example.com\n===END===")
    end

    assert_equal :error, @results.first[:status]
    cr = @vessel.command_responses.last
    assert_equal "body", cr.source
    assert_match(/ERR/, cr.response_text)
    assert_match(/Empty message/i, cr.response_text)
  end

  test "SEND with an unknown account queues an error response" do
    assert_difference "@vessel.command_responses.count", 1 do
      @vessel.parse_and_execute_commands("===CMD===\nSEND.ZZ bob@example.com \"hi\"\n===END===")
    end

    cr = @vessel.command_responses.last
    assert_match(/Unknown account short_code: ZZ/, cr.response_text)
  end

  test "GET with no match queues an error response" do
    assert_difference "@vessel.command_responses.count", 1 do
      @vessel.parse_and_execute_commands("===CMD===\nGET 99dec.ZZ.9\n===END===")
    end

    cr = @vessel.command_responses.last
    assert_equal "body", cr.source
    assert_match(/ERR/, cr.response_text)
  end

  test "malformed MSG block queues an error response" do
    assert_difference "@vessel.command_responses.count", 1 do
      @vessel.parse_and_execute_commands("===MSG bob@example.com===\nbody\n===END===")
    end

    cr = @vessel.command_responses.last
    assert_equal "body", cr.source
    assert_match(/Invalid format/i, cr.response_text)
  end

  test "unknown REPLY reference queues an error response" do
    assert_difference "@vessel.command_responses.count", 1 do
      @vessel.parse_and_execute_commands("===REPLY 99dec.ZZ.9===\nbody\n===END===")
    end

    cr = @vessel.command_responses.last
    assert_match(/Unknown hutmail_id/, cr.response_text)
  end

  test "subject accepts only the immediate-answer verbs" do
    assert_no_difference "@vessel.command_responses.count" do
      assert_empty @vessel.parse_and_execute_subject("PAUSE 2h")
    end
  end

  test "subject without a command verb is ignored" do
    assert_no_difference "@vessel.command_responses.count" do
      assert_empty @vessel.parse_and_execute_subject("Re: bundle 23may 09:15")
    end
  end

  test "subject strips Re:/Fwd: prefixes before parsing" do
    assert_difference "@vessel.command_responses.count", 1 do
      @vessel.parse_and_execute_subject("Re: Fwd: STATUS")
    end
    assert_equal "STATUS", @vessel.command_responses.last.command
  end

  # ------------------------------------------------------------------
  # Information: STATUS / PING / HELP
  # ------------------------------------------------------------------

  test "STATUS from body queues a deferred response" do
    assert_no_enqueued_jobs only: CommandResponse::DeliverJob do
      assert_difference "@vessel.command_responses.count", 1 do
        results = @vessel.parse_and_execute_commands("===CMD===\nSTATUS\n===END===")
        assert_equal "STATUS", results.first[:command]
        assert_equal :ok, results.first[:status]
        assert_includes results.first[:message], "ready for bundling"
      end
    end
    cr = @vessel.command_responses.last
    assert_equal "body", cr.source
    assert_equal "pending", cr.status
  end

  test "STATUS from subject is answered immediately" do
    assert_difference "@vessel.command_responses.count", 1 do
      assert_enqueued_with(job: CommandResponse::DeliverJob) do
        @vessel.parse_and_execute_subject("STATUS")
      end
    end

    cr = @vessel.command_responses.last
    assert_equal "subject", cr.source
    assert_equal "STATUS", cr.command
    assert_match(/STATUS hutmail/, cr.response_text)
  end

  test "PING returns PONG with a UTC timestamp" do
    @vessel.parse_and_execute_subject("PING")
    cr = @vessel.command_responses.last

    assert_equal "PING", cr.command
    assert_match(/\APONG \d{4}-\d{2}-\d{2}T\d{2}:\d{2}Z hutmail\z/, cr.response_text)
  end

  test "HELP lists the available commands" do
    @vessel.parse_and_execute_subject("HELP")
    cr = @vessel.command_responses.last

    assert_equal "HELP", cr.command
    assert_match(/HUTMAIL commands/, cr.response_text)
  end

  # ------------------------------------------------------------------
  # Retrieval: GET (with implicit wildcards)
  # ------------------------------------------------------------------

  test "GET resolves a fully-qualified reference to a single message" do
    assert_equal [ "01mar.GM.1" ], get_references("01mar.GM.1")
  end

  test "GET narrows to a mailbox on a given day" do
    assert_equal [ "01mar.GM.1" ], get_references("01mar.GM")
  end

  test "GET on a day matches every mailbox" do
    assert_equal [ "01mar.GM.1", "01mar.OR.1" ], get_references("01mar")
  end

  test "GET on a mailbox code matches every date" do
    assert_equal [ "01mar.GM.1", "28feb.GM.2" ], get_references("GM")
  end

  test "GET on a bare sequence number matches across mailboxes and dates" do
    assert_equal [ "01mar.GM.1", "01mar.OR.1" ], get_references("1")
  end

  test "GET accepts several references at once" do
    assert_equal [ "01mar.GM.1", "28feb.GM.2" ], get_references("01mar.GM.1 28feb.GM.2")
  end

  test "GET with no match returns an error and bundles nothing" do
    captured = nil
    @vessel.define_singleton_method(:dispatch_get_response) { |messages| captured = messages }

    results = @vessel.parse_and_execute_commands("===CMD===\nGET 99dec.ZZ.9\n===END===")

    assert_nil captured
    assert_equal :error, results.first[:status]
    assert_match(/No matching messages/, results.first[:message])
  end

  test "GET from the subject line is honored" do
    refs = nil
    @vessel.define_singleton_method(:dispatch_get_response) { |messages| refs = messages.map(&:hutmail_reference) }

    results = @vessel.parse_and_execute_subject("GET 01mar.GM.1")

    assert_equal [ "01mar.GM.1" ], refs
    assert_equal :ok, results.first[:status]
  end

  test "GET retrieves an already-bundled message regardless of status" do
    create_digest(short_code: :gmail, from: "alice@example.com", subject: "Already sent",
      date: Date.new(2026, 6, 8), seq: 1, uid: 500, status: "bundled")

    refs = nil
    @vessel.define_singleton_method(:dispatch_get_response) { |messages| refs = messages.map(&:hutmail_reference) }

    results = @vessel.parse_and_execute_commands("===CMD===\nGET 08jun.GM.1\n===END===")

    assert_equal [ "08jun.GM.1" ], refs
    assert_equal :ok, results.first[:status]
  end

  test "GET retrieves a no_longer_collectable message" do
    create_digest(short_code: :gmail, from: "bob@example.com", subject: "Stale",
      date: Date.new(2026, 6, 8), seq: 2, uid: 501, status: "no_longer_collectable")

    refs = nil
    @vessel.define_singleton_method(:dispatch_get_response) { |messages| refs = messages.map(&:hutmail_reference) }

    @vessel.parse_and_execute_commands("===CMD===\nGET 08jun.GM.2\n===END===")

    assert_equal [ "08jun.GM.2" ], refs
  end

  test "GET with a broad short-code wildcard still excludes bundled messages" do
    MessageDigest.where(mail_account: mail_accounts(:gmail)).delete_all
    create_digest(short_code: :gmail, from: "a@example.com", subject: "Fresh",
      date: Date.new(2026, 6, 8), seq: 1, uid: 600, status: "collected")
    create_digest(short_code: :gmail, from: "b@example.com", subject: "Sent already",
      date: Date.new(2026, 6, 8), seq: 2, uid: 601, status: "bundled")

    refs = nil
    @vessel.define_singleton_method(:dispatch_get_response) { |messages| refs = messages.map(&:hutmail_reference) }

    @vessel.parse_and_execute_commands("===CMD===\nGET GM\n===END===")

    assert_equal [ "08jun.GM.1" ], refs
  end

  # ------------------------------------------------------------------
  # Outbound: REPLY / MSG / SEND / URGENT
  # ------------------------------------------------------------------

  test "REPLY resolves the original by reference and threads the answer" do
    original = create_digest(short_code: :gmail, from: "alice@example.com",
      subject: "Original subject", date: Date.new(2026, 5, 22), seq: 3, uid: 100)

    text = "===REPLY 22may.GM.3===\nQuick reply from the boat\n===END==="
    results = @vessel.parse_and_execute_commands(text)

    reply = @vessel.vessel_replies.order(:id).last
    assert_equal original, reply.message_digest
    assert_equal "alice@example.com", reply.to_address
    assert_equal "Re: Original subject", reply.subject
    assert_equal mail_accounts(:gmail), reply.mail_account
    assert_equal :ok, results.first[:status]
  end

  test "REPLY does not double-prefix an already-Re: subject" do
    create_digest(short_code: :gmail, from: "bob@example.com",
      subject: "Re: existing thread", date: Date.new(2026, 5, 22), seq: 7, uid: 43)

    @vessel.parse_and_execute_commands("===REPLY 22may.GM.7===\nReply body\n===END===")

    assert_equal "Re: existing thread", @vessel.vessel_replies.order(:id).last.subject
  end

  test "REPLY with an unknown reference reports an error and creates nothing" do
    assert_no_difference "@vessel.vessel_replies.count" do
      @results = @vessel.parse_and_execute_commands("===REPLY 99dec.ZZ.9===\nbody\n===END===")
    end

    assert_equal :error, @results.first[:status]
    assert_match(/Unknown hutmail_id/, @results.first[:message])
  end

  test "MSG.<ACCOUNT> creates a fresh outbound message via that account" do
    text = "===MSG.GM bob@example.com===\nHello from the sea!\n===END==="
    results = @vessel.parse_and_execute_commands(text)

    reply = @vessel.vessel_replies.order(:id).last
    assert_equal "MSG.GM bob@example.com", results.first[:command]
    assert_equal :ok, results.first[:status]
    assert_equal "bob@example.com", reply.to_address
    assert_equal mail_accounts(:gmail), reply.mail_account
    assert_nil reply.message_digest
    assert_equal "Hutmail message", reply.subject
  end

  test "MSG without an account short_code is rejected" do
    assert_no_difference "@vessel.vessel_replies.count" do
      @results = @vessel.parse_and_execute_commands("===MSG bob@example.com===\nbody\n===END===")
    end

    assert_equal :error, @results.first[:status]
    assert_match(/Invalid format/, @results.first[:message])
  end

  test "MSG with an unknown account short_code is rejected" do
    assert_no_difference "@vessel.vessel_replies.count" do
      @results = @vessel.parse_and_execute_commands("===MSG.XX bob@example.com===\nbody\n===END===")
    end

    assert_equal :error, @results.first[:status]
    assert_match(/Unknown account short_code: XX/, @results.first[:message])
  end

  test "REPLY and MSG can be mixed in the same payload" do
    original = create_digest(short_code: :gmail, from: "alice@example.com",
      subject: "Topic A", date: Date.new(2026, 5, 22), seq: 1, uid: 200)

    text = <<~TEXT
      ===REPLY 22may.GM.1===
      Reply to A
      ===MSG.OR bob@new.example===
      Spontaneous message via Orange
      ===END===
    TEXT
    @vessel.parse_and_execute_commands(text)

    replies = @vessel.vessel_replies.order(:id).last(2)
    reply = replies.find { |r| r.to_address == "alice@example.com" }
    msg   = replies.find { |r| r.to_address == "bob@new.example" }

    assert_equal original, reply.message_digest
    assert_equal "Re: Topic A", reply.subject
    assert_nil msg.message_digest
    assert_equal mail_accounts(:orange), msg.mail_account
  end

  test "SEND.<ACCOUNT> queues a message via the named account" do
    results = @vessel.parse_and_execute_commands("===CMD===\nSEND.GM bob@example.com \"Quick note\"\n===END===")

    reply = @vessel.vessel_replies.order(:id).last
    assert_equal "bob@example.com", reply.to_address
    assert_equal mail_accounts(:gmail), reply.mail_account
    assert_equal "Quick note", reply.body
    assert_equal :ok, results.first[:status]
    assert_equal "SEND.GM bob@example.com", results.first[:command]
  end

  test "SEND without an account short_code is rejected" do
    assert_no_difference "@vessel.vessel_replies.count" do
      @results = @vessel.parse_and_execute_commands("===CMD===\nSEND bob@example.com \"Hello\"\n===END===")
    end

    assert_equal :error, @results.first[:status]
    assert_match(/Invalid format/, @results.first[:message])
  end

  test "SEND with an unknown account short_code is rejected" do
    assert_no_difference "@vessel.vessel_replies.count" do
      @results = @vessel.parse_and_execute_commands("===CMD===\nSEND.ZZ bob@example.com \"body\"\n===END===")
    end

    assert_equal :error, @results.first[:status]
    assert_match(/Unknown account short_code: ZZ/, @results.first[:message])
  end

  test "URGENT.<ACCOUNT> delivers immediately" do
    reply = nil
    assert_difference "@vessel.vessel_replies.count", 1 do
      results = @vessel.parse_and_execute_commands("===CMD===\nURGENT.GM bob@example.com \"NOW\"\n===END===")
      assert_equal :ok, results.first[:status]
      assert_equal "URGENT.GM bob@example.com", results.first[:command]
    end
    reply = @vessel.vessel_replies.order(:id).last
    assert_equal mail_accounts(:gmail), reply.mail_account
  end

  test "SEND accepts the message on the lines below the command" do
    text = "===CMD===\nSEND.GM bob@example.com\nEssai de message\nsur plusieurs lignes\n===END==="
    results = @vessel.parse_and_execute_commands(text)

    reply = @vessel.vessel_replies.order(:id).last
    assert_equal "bob@example.com", reply.to_address
    assert_equal mail_accounts(:gmail), reply.mail_account
    assert_equal "Essai de message\nsur plusieurs lignes", reply.body
    assert_equal :ok, results.first[:status]
  end

  test "URGENT accepts a multiline message and delivers immediately" do
    text = "===CMD===\nURGENT.GM bob@example.com\nEssai de message urgent 1233\n===END==="
    assert_difference "@vessel.vessel_replies.count", 1 do
      results = @vessel.parse_and_execute_commands(text)
      assert_equal :ok, results.first[:status]
    end

    reply = @vessel.vessel_replies.order(:id).last
    assert_equal "Essai de message urgent 1233", reply.body
    assert_equal mail_accounts(:gmail), reply.mail_account
  end

  test "multiline SEND stops at the next command" do
    text = "===CMD===\nSEND.GM bob@example.com\nFirst message body\nSTATUS\n===END==="
    results = @vessel.parse_and_execute_commands(text)

    reply = @vessel.vessel_replies.order(:id).last
    assert_equal "First message body", reply.body
    assert(results.any? { |r| r[:command] == "STATUS" })
  end

  test "inline SEND with message on the same line still works" do
    text = "===CMD===\nSEND.GM bob@example.com \"Quick inline note\"\n===END==="
    @vessel.parse_and_execute_commands(text)

    reply = @vessel.vessel_replies.order(:id).last
    assert_equal "Quick inline note", reply.body
  end

  test "multiline URGENT with an unknown account queues an error" do
    text = "===CMD===\nURGENT.ZZ bob@example.com\nsome text\n===END==="
    assert_no_difference "@vessel.vessel_replies.count" do
      @vessel.parse_and_execute_commands(text)
    end

    cr = @vessel.command_responses.last
    assert_match(/Unknown account short_code: ZZ/, cr.response_text)
  end

  # ------------------------------------------------------------------
  # Custom subject via OBJET directive (SEND / URGENT / MSG)
  # ------------------------------------------------------------------

  test "multiline SEND uses the OBJET directive as subject" do
    text = "===CMD===\nSEND.GM bob@example.com\nOBJET Arrivée mardi /OBJET\nOn arrive à Horta.\n===END==="
    @vessel.parse_and_execute_commands(text)

    reply = @vessel.vessel_replies.order(:id).last
    assert_equal "Arrivée mardi", reply.subject
    assert_equal "On arrive à Horta.", reply.body
  end

  test "multiline URGENT uses the OBJET directive as subject" do
    text = "===CMD===\nURGENT.GM bob@example.com\nOBJET Alerte météo /OBJET\nGros grain en approche\n===END==="
    @vessel.parse_and_execute_commands(text)

    reply = @vessel.vessel_replies.order(:id).last
    assert_equal "Alerte météo", reply.subject
    assert_equal "Gros grain en approche", reply.body
  end

  test "MSG uses the OBJET directive as subject" do
    text = "===MSG.GM bob@example.com===\nOBJET Coucou /OBJET\nDes nouvelles du large\n===END==="
    @vessel.parse_and_execute_commands(text)

    reply = @vessel.vessel_replies.order(:id).last
    assert_equal "Coucou", reply.subject
    assert_equal "Des nouvelles du large", reply.body
  end

  test "OBJET directive is case insensitive" do
    text = "===MSG.GM bob@example.com===\nobjet Tout va bien /objet\nLe corps\n===END==="
    @vessel.parse_and_execute_commands(text)

    reply = @vessel.vessel_replies.order(:id).last
    assert_equal "Tout va bien", reply.subject
  end

  test "no OBJET directive keeps the default subject" do
    text = "===CMD===\nSEND.GM bob@example.com\nMessage sans objet\n===END==="
    @vessel.parse_and_execute_commands(text)

    reply = @vessel.vessel_replies.order(:id).last
    assert_equal "Hutmail message", reply.subject
    assert_equal "Message sans objet", reply.body
  end

  test "OBJET directive does not apply to REPLY" do
    original = create_digest(short_code: :gmail, from: "alice@example.com",
      subject: "Topic A", date: Date.new(2026, 5, 22), seq: 1, uid: 300)

    text = "===REPLY 22may.GM.1===\nOBJET ignored here /OBJET\nThe reply body\n===END==="
    @vessel.parse_and_execute_commands(text)

    reply = @vessel.vessel_replies.order(:id).last
    assert_equal original, reply.message_digest
    assert_equal "Re: Topic A", reply.subject
    assert_equal "OBJET ignored here /OBJET\nThe reply body", reply.body
  end

  # ------------------------------------------------------------------
  # Aggregation control: PAUSE / RESUME
  # ------------------------------------------------------------------

  test "PAUSE is acknowledged" do
    results = @vessel.parse_and_execute_commands("===CMD===\nPAUSE 3d\n===END===")

    assert_equal :ok, results.first[:status]
    assert_match(/paused/i, results.first[:message])
  end

  test "RESUME is acknowledged" do
    results = @vessel.parse_and_execute_commands("===CMD===\nRESUME\n===END===")

    assert_equal :ok, results.first[:status]
    assert_match(/resumed/i, results.first[:message])
  end

  # ------------------------------------------------------------------
  # Sender lists: WHITELIST / BLACKLIST
  # ------------------------------------------------------------------

  test "WHITELIST is acknowledged" do
    results = @vessel.parse_and_execute_commands("===CMD===\nWHITELIST add bob@example.com\n===END===")

    assert_equal :ok, results.first[:status]
    assert_match(/whitelist updated/i, results.first[:message])
  end

  test "BLACKLIST is acknowledged" do
    results = @vessel.parse_and_execute_commands("===CMD===\nBLACKLIST add spam@junk.com\n===END===")

    assert_equal :ok, results.first[:status]
    assert_match(/blacklist updated/i, results.first[:message])
  end

  private
    def get_references(args)
      refs = nil
      @vessel.define_singleton_method(:dispatch_get_response) do |messages|
        refs = messages.to_a.map(&:hutmail_reference)
      end
      seed_get_corpus
      @vessel.parse_and_execute_commands("===CMD===\nGET #{args}\n===END===")
      refs.sort
    end

    def seed_get_corpus
      MessageDigest.where(mail_account: @vessel.mail_accounts).delete_all
      create_digest(short_code: :gmail,  from: "bob@example.com",  subject: "Horta",   date: Date.new(2026, 3, 1),  seq: 1, uid: 100)
      create_digest(short_code: :gmail,  from: "mom@family.fr",    subject: "News",    date: Date.new(2026, 2, 28), seq: 2, uid: 101)
      create_digest(short_code: :orange, from: "boss@work.com",    subject: "Invoice", date: Date.new(2026, 3, 1),  seq: 1, uid: 102)
    end

    def create_digest(short_code:, from:, subject:, date:, seq:, uid:, status: "collected")
      mail_accounts(short_code).message_digests.create!(
        from_address: from,
        subject: subject,
        date: date,
        imap_message_id: "#{from}-#{uid}@example.com",
        imap_uid: uid,
        raw_size: 100, stripped_body: "hi", stripped_size: 2,
        daily_sequence: seq, status: status,
        collected_at: date.beginning_of_day
      )
    end
end

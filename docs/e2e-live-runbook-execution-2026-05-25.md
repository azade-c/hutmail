# Live E2E execution — 2026-05-25

Run of [`e2e-live-runbook.md`](./e2e-live-runbook.md) against production (`hutmail.azade.dev`),
no code changes, vessel `#1` ("Alibi • test") on the existing francemel/netcourrier mailbox pair.

**Result: 🟢 PASS** on all exercised scenarios (A, B, C, plus an added round 3 covering
the outbound sailor→world path via `===MSG===` and `===REPLY===` blocks, and a Gmail external sender).
Scenario D (mixed subject + body command in one inbound) not run live (covered by
`test/integration/scheduling_and_commands_e2e_test.rb`).

## Timeline (UTC)

| Time | Event | Source |
|---|---|---|
| 19:23:04 | Vessel armed: cadence=every_hours/1, next_dispatch_at=past | Rails console |
| 19:25:00 | Scheduler tick fired, found vessel due, dispatched empty bundle (no mail yet) | `last_dispatched_at` |
| 19:26:03 | `azade@hey.com` → `alibi@francemel.fr` subj `E2E-LIVE-R1-HEY 2026-05-25` | HEY UI |
| 19:27:49 | Re-armed `next_dispatch_at` (vessel due again) | Rails console |
| **19:30:01** | **Scheduler tick → `Vessel::DispatchJob` → collect + compose `Bundle#14`** | Server |
| 19:30:03 | Bundle#14 sent (1 msg, outbound_message_id=`<6a14a339...@...mail>`) | `Bundle#sent_at` |
| ~19:30 | netcourrier received `HUTMAIL 25may 19:30`, body matches `bundle_text` verbatim | sailmail UI |
| 19:33 | `azade@hey.com` → `alibi@francemel.fr` subj `E2E-LIVE-R2-HEY 2026-05-25` (round 2 external) | HEY UI |
| 19:37:40 | `sailmailalibi@netcourrier.com` → `alibi@francemel.fr` subj `PING` (subject command) | netcourrier UI |
| 19:41:29 | sailmail → relay subj `E2E-LIVE-R2-BODYCMD`, body `===CMD===\nSTATUS\n===END===` | netcourrier UI |
| **19:40:02** | **`RelayPollJob` tick → parsed subject `PING` → `cr#1 status=sent`** | Server |
| 19:40:03 | `CommandResponseMailer.send_response` delivered PONG | `cr#1.updated_at` |
| ~19:40 | netcourrier received subj `HUTMAIL PING` body `PONG 2026-05-25T19:40Z hutmail` | sailmail UI |
| **19:45:00** | **`RelayPollJob` tick → parsed body `STATUS` → `cr#2 status=pending`** | Server |
| 19:47:07 | Re-armed `next_dispatch_at` | Rails console |
| **19:50:01** | **`DispatchJob` → collected R2-HEY md#53, composed `Bundle#15` folding in cr#2** | Server |
| 19:50:03 | Bundle#15 sent (1 msg + 1 cr, outbound_message_id=`<6a14a7e9...@...mail>`) | `Bundle#sent_at` |
| ~19:50 | netcourrier received `HUTMAIL 25may 19:50` with both STATUS-response block and R2-HEY digest | sailmail UI |
| 19:51 | Vessel restored to `manual` cadence (intermediate cleanup) | Rails console |
| 20:12:36 | Vessel re-armed for round 3 (cadence=every_hours/1, next=past) | Rails console |
| 20:13:51 | `azade.craba@gmail.com` → `alibi@francemel.fr` subj `E2E-LIVE-R3-GMAIL 2026-05-25` (round 3 external) | Gmail UI |
| **20:15:00** | **Scheduler tick → DispatchJob → collected Gmail md#54, composed `Bundle#16`** | Server |
| 20:15:03 | Bundle#16 sent (1 msg, outbound_message_id=`<6a14adc4...@...mail>`) | `Bundle#sent_at` |
| 20:46:31 | sailmail → relay subj `E2E-LIVE-R3-OUTBOUND` with composite body: 2× `===MSG.AL …===` + 1× `===REPLY 25may.AL.2===` | netcourrier UI |
| **20:50:00** | **`RelayPollJob` tick → parsed 3 outbound blocks → 3 `VesselReply` rows created** | Server |
| 20:50:02 | vr#11 (MSG→hey) delivered, outbound_message_id=`<6a14b5f8c1ae7…@…mail>` | Server |
| 20:50:04 | vr#13 (REPLY→hey, threaded) delivered, outbound_message_id=`<6a14b5fb1fc13…@…mail>` | Server |
| 20:50:08 | vr#12 (MSG→gmail) delivered, outbound_message_id=`<6a14b5f8c312f…@…mail>` | Server |
| ~20:50 | HEY Imbox received MSG (standalone) and REPLY (grouped inside R2 thread). Gmail Primary received MSG. All DKIM/SPF/DMARC pass | hey/gmail UIs |
| 21:02 | Vessel restored to `manual` cadence (final cleanup) | Rails console |

## Assertions (Scenario A — scheduled bundling)

```
MessageDigest #52: subject="E2E-LIVE-R1-HEY 2026-05-25" from="azade@hey.com"
                   status=bundled created=2026-05-25T19:30:01Z
Bundle #14:        status=sent msgs=1 remaining=0
                   outbound_message_id="<6a14a339e0e6b_2939e893077@46.224.183.194-c75bb9418c20.mail>"
                   sent=2026-05-25T19:30:03Z
Vessel #1:         last_dispatched_at=2026-05-25T19:30:10Z next_dispatch_at=2026-05-25T20:30:10Z
```

Bundle text (verbatim, server-side):

```
=== HUTMAIL 25may 19:30 ===

==[ AL — Alibi @ francemel (alibi@francemel.fr) ]==

[25may.AL.1] From: Azade <azade@hey.com> | E2E-LIVE-R1-HEY 2026-05-25 | 25may 19:26
Round 1 message from azade@hey.com to alibi@francemel.fr.
Tag: E2E-LIVE-R1-HEY
Sent at: 2026-05-25T19:25:24Z

=== END ===
```

Confirmed byte-for-byte identical in the netcourrier sailmail inbox, received 21:30 Paris (= 19:30 UTC).

## Assertions (Scenario B — subject command, immediate)

```
CommandResponse #1: source=subject command="PING" status=sent bundle_id=nil
                    response_text="PONG 2026-05-25T19:40Z hutmail"
                    created=2026-05-25T19:40:02Z updated=2026-05-25T19:40:03Z
```

netcourrier received subject `HUTMAIL PING`, body `PONG 2026-05-25T19:40Z hutmail` at ~21:40 Paris.

## Assertions (Scenario E — outbound MSG + REPLY from sailor to external world)

(Round 3, added after the original A/B/C run to plug the outbound gap.)

Server-side after the 20:50 `RelayPollJob` tick:

```
VesselReply #11: to="azade@hey.com"           subj="Hutmail message"                 md_id=nil  status=sent  sent=20:50:02Z  outbound_message_id="<6a14b5f8c1ae7_293fb0934b3@46.224.183.194-c75bb9418c20.mail>"
VesselReply #12: to="azade.craba@gmail.com"   subj="Hutmail message"                 md_id=nil  status=sent  sent=20:50:08Z  outbound_message_id="<6a14b5f8c312f_294030935b1@46.224.183.194-c75bb9418c20.mail>"
VesselReply #13: to="azade@hey.com"           subj="Re: E2E-LIVE-R2-HEY 2026-05-25"  md_id=53   status=sent  sent=20:50:04Z  outbound_message_id="<6a14b5fb1fc13_293fb09369c@46.224.183.194-c75bb9418c20.mail>"
```

Recipient-side verification (via `agent-browser`):

- **HEY (azade@hey.com)** — both messages arrived directly in Imbox (sender already approved):
  - vr#11: standalone thread, no `In-Reply-To` header, DKIM/SPF/DMARC all `pass`.
  - vr#13: grouped **inside** the original `E2E-LIVE-R2-HEY 2026-05-25` thread by HEY's UI.
    Raw headers show `In-Reply-To: <3f1e742db8ddcad78acdb811e5e0ecbc0b11f685@hey.com>` and
    `References: <3f1e742db8ddcad78acdb811e5e0ecbc0b11f685@hey.com>` — exactly the
    `imap_message_id` of `MessageDigest#53`, which `OutboundMailer#threading_headers_for`
    pulls via `vessel_reply.message_digest&.imap_message_id`. DKIM/SPF/DMARC all `pass`.
- **Gmail (azade.craba@gmail.com)** — vr#12 landed in **Primary inbox** (not Spam), Gmail's
  "Delivered after 8 seconds" header confirms low SMTP latency. `Show original` confirms
  Message-ID byte-identical with the server-side record. DKIM/SPF/DMARC all `pass`.
  Routing: `mailo.com (msg-4.mailo.com [213.182.54.15])` → `mx.google.com`.
- **No misdelivery** — Bundle#16 (the inbound gmail-external bundle) was correctly routed
  to netcourrier sailmail only, not bounced back to gmail.

This closes the loop: sailor on SSB can now compose brand-new mail or threaded replies
to external recipients, and Hutmail correctly bridges `===MSG===`/`===REPLY===` blocks to
real SMTP with proper threading headers.

## Assertions (Scenario C — body command, deferred + bundled with new external)

After the poll tick at 19:45:

```
CommandResponse #2: source=body command="STATUS" status=pending bundle_id=nil
                    response_text="STATUS hutmail\nready: 0 messages\nbudget: 697.7 KB remaining (7d)\n
                                   last dispatch: 25may 19:30z\nnext dispatch: 25may 20:30z (every_hours)"
```

After the dispatch tick at 19:50:

```
CommandResponse #2: status=pending → included, bundle_id=15
MessageDigest #53:  subject="E2E-LIVE-R2-HEY 2026-05-25" status=bundled
Bundle #15:         status=sent msgs=1 remaining=0
                    outbound_message_id="<6a14a7e945a79_293c2893262@46.224.183.194-c75bb9418c20.mail>"
```

Bundle text:

```
=== HUTMAIL 25may 19:50 ===

==[ ✉ STATUS response ]==
STATUS hutmail
ready: 0 messages
budget: 697.7 KB remaining (7d)
last dispatch: 25may 19:30z
next dispatch: 25may 20:30z (every_hours)

==[ AL — Alibi @ francemel (alibi@francemel.fr) ]==

[25may.AL.2] From: Azade <azade@hey.com> | E2E-LIVE-R2-HEY 2026-05-25 | 25may 19:33
Round 2 message from azade@hey.com to alibi@francemel.fr.
This should land in the next Hutmail bundle alongside the deferred
STATUS command response.
Tag: E2E-LIVE-R2-HEY
Sent at: 2026-05-25 13:42 UTC

=== END ===
```

Confirmed byte-for-byte in netcourrier inbox at 21:50 Paris.

## Latency / observations

- **Dispatch latency**: collect+compose+send = 2 seconds (Bundle#14 `created→sent` = 19:30:01→19:30:03; Bundle#15 = 19:50:01→19:50:03). SMTP via Mailo is snappy.
- **End-to-end mail latency**: sailmail receives bundle within seconds of `sent_at`. No measurable delay.
- **Scheduler precision**: Solid Queue's recurring tick fires within ~1 second of the wall-clock `:00 / :05 / :10` UTC boundary. Predictable.
- **Loopback safety**: the relay account and mail account share a mailbox (`alibi@francemel.fr`).
  Despite that, the sailor's PING / PONG / BODYCMD emails did NOT bleed into MessageDigests.
  The relay polling correctly marks UIDs processed before mail-account collection sees them
  (or skip_already_read filters them). No contamination after 2 rounds.
- **`response_text` source-of-truth check**: server-side `cr#2.response_text` matches verbatim
  the `==[ ✉ STATUS response ]==` block embedded in Bundle#15 — folding logic preserves
  formatting.
- **Hey body timestamp typo**: the round-2 body said "Sent at: 2026-05-25 13:42 UTC" — the
  agent typed local NY time. Did not affect any assertion (Hutmail records the actual SMTP
  envelope/header timestamp shown as `25may 19:33` in the bundle index line). Cosmetic.

## Issues surfaced

1. **Gmail send was initially blocked** in headless and even in `--executable-path` real-Chrome
   mode because the "Profile 2" was logged out and Google's anti-bot rejected re-auth from a
   CDP-attached browser. After a manual Chrome sign-in, round 3's Gmail send and the inbound
   Gmail-side verification both worked first try. Suggest updating AGENTS.md so the next agent
   knows to keep the Azade profile signed in (or to use `--auto-connect` against an already-running
   Chrome window).
2. **Thin logging in dispatch/poll jobs** — verifying server-side required reading DB state via
   console; log files alone wouldn't tell the story. Out of scope for this no-code-change exercise,
   but worth a small follow-up PR adding `Rails.logger.info` tags around:
   - `Vessel::DispatchJob#perform` (vessel id, messages_to_bundle.size, bundle id, decision)
   - `Vessel#parse_and_execute_subject`/`parse_and_execute_commands` (vessel id, command, source, decision)
   - `CommandResponse::DeliverJob#perform` (cr id, status transition)
3. **Mail-account collection happens only during DispatchJob**, not on `RelayPollJob` ticks. This
   is by design (collection is bandwidth-coupled with bundling) but means a new external email
   sitting in the inbox is invisible to the system until the next dispatch tick. Documented here
   for future debugging — not a bug.

No regressions, no flakiness, no bugs surfaced. Pipeline behaves exactly as the stubbed
integration test predicted.

## Cleanup performed

- `Vessel#1` restored: `dispatch_cadence: "manual", dispatch_every_hours: nil,
  last_dispatched_at: nil, next_dispatch_at: nil`. Verified `Vessel.due_for_dispatch == []`.
- Test bundles (#14, #15, #16), MessageDigests (#52, #53, #54), CommandResponses (#1, #2),
  and VesselReplies (#11, #12, #13) left in DB as audit trail.
- No code changed, no migration applied, no deploy. Container untouched.

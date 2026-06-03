# Live E2E runbook — scheduled bundling + command routing

End-to-end verification of the cron-driven pipeline against **real IMAP/SMTP** mail servers,
using the production deployment. Stubs the test suite proves the wiring; this runbook proves
the wiring talks to real mailboxes on a real schedule.

- Target env: production (`hutmail.azade.dev`, Kamal, Solid Queue in-Puma)
- Recurring scheduler: `config/recurring.yml` → `DispatchDueVesselsJob` and `RelayPollJob`
  every 5 minutes on `:00, :05, :10, ...` UTC boundaries.
- Vessel under test: existing `Vessel#1` ("Alibi • test"). No new vessel created.
- **No code changes** — only ephemeral DB state changes via `bin/kamal console`, fully reverted at the end.

## Cadence strategy (option **b**)

`Vessel#dispatch_every_hours` validates `1..24`, so a true sub-hour cadence is illegal.
Instead we:

1. `update_columns` (skips validations + skips the `recompute_next_dispatch_at` callback)
   to set `dispatch_cadence: "every_hours", dispatch_every_hours: 1, next_dispatch_at: 1.minute.ago`.
2. The next 5-minute scheduler tick sees the vessel as due, fires `Vessel::DispatchJob`.
3. After dispatch, the job re-computes `next_dispatch_at = last + 1.hour` (1h out).
4. Between rounds we re-arm with `update_columns(next_dispatch_at: 1.minute.ago)`.

`RelayPollJob` polls every 5 min unconditionally and needs no nudging.

## Test accounts

| Role | Address | Vault entry | Purpose |
|---|---|---|---|
| Mail account (external arrivals) | `alibi@francemel.fr` | `francemel-alibi` | The sailor's shore-side mailbox; Hutmail collects from here |
| Relay account (sailor SSB side) | `alibi@francemel.fr` | `francemel-alibi` | Hutmail polls this for sailor-originated commands. Same mailbox as the mail account — Mailo backend, dual-purpose for this test vessel |
| Sailmail (sailor reads bundles here) | `sailmailalibi@netcourrier.com` | `netcourrier-sailmail` | Hutmail sends bundles to this address; sailor's "send" address back to relay |
| External sender 1 | `azade@hey.com` | `hey-azade` | Drives real inbound mail |
| External sender 2 | `azade.craba@gmail.com` | (real Chrome profile) | Second sender — see Gmail caveat below |

> **Gmail caveat**: `azade.craba@gmail.com` requires the real Chrome binary with the Azade profile
> clone (`--executable-path "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --profile "Profile 2"`).
> If the profile is logged out, Google blocks re-auth from the CDP-attached browser. Sign in manually
> first, then attach with `--auto-connect`.

## Pre-flight

```bash
bin/kamal app exec --reuse "bash -c 'echo <base64-of-inspect_vessels.rb> | base64 -d | bin/rails runner /dev/stdin'"
```

Snapshot baseline: vessel cadence, last/next dispatch, latest Bundle id, latest MessageDigest id,
latest CommandResponse id. You'll diff against these after each round.

Then arm the vessel (script `/tmp/configure_vessel.rb`):

```ruby
v = Vessel.find(1)
v.update_columns(
  dispatch_cadence: "every_hours",
  dispatch_every_hours: 1,
  dispatch_timezone: "UTC",
  last_dispatched_at: nil,
  next_dispatch_at: 1.minute.ago
)
```

Assert `Vessel.due_for_dispatch.pluck(:id) == [1]`.

## Scenario A — Scheduled bundling

1. Send one external email from `azade@hey.com` to `alibi@francemel.fr` with a
   unique tag in subject and body (`E2E-LIVE-R1-HEY <date>`). Optionally a second
   from Gmail. Note the exact UTC send timestamp.
2. Re-arm: `Vessel.find(1).update_columns(next_dispatch_at: 1.minute.ago)`.
3. Wait until the next `:00 / :05 / :10 / ...` UTC tick passes by ≥30s.
4. **Assertions (Rails console)**:
   - New `MessageDigest` exists, `status: "bundled"`, matching subject/from.
   - New `Bundle` exists with `status: "sent"`, `messages_count >= 1`, `outbound_message_id` not nil.
   - `bundle_text` contains the tag from step 1.
   - `Vessel#1`: `last_dispatched_at` updated, `next_dispatch_at` 1h out.
5. **Assertion (mailbox)** — log in to netcourrier as `sailmailalibi@netcourrier.com`
   and confirm receipt of `HUTMAIL <date> <HH:MM>` email from `alibi@francemel.fr`.
   Body matches `bundle_text`. Received-time within a couple seconds of `Bundle#sent_at`.

## Scenario B — Subject command (immediate)

1. From sailmail (`sailmailalibi@netcourrier.com`) send to `alibi@francemel.fr`:
   `Subject: PING`, body irrelevant.
2. Wait until the next `:00 / :05 / ...` tick passes (RelayPollJob).
3. **Assertions**:
   - New `CommandResponse` with `source: "subject", command: "PING", status: "sent"`, `bundle_id: nil`.
   - `response_text` matches `/\APONG \d{4}-\d{2}-\d{2}T\d{2}:\d{2}Z hutmail\z/`.
4. **Mailbox assertion**: sailmail inbox receives a one-liner from `alibi@francemel.fr`,
   subject `HUTMAIL PING`, body = the `PONG …` line above. Within seconds of the poll tick.

## Scenario C — Body command (deferred, folded into bundle)

1. From sailmail send to `alibi@francemel.fr`:
   - `Subject: E2E-LIVE-R2-BODYCMD`
   - Body (plain text, exact):
     ```
     Hello, requesting STATUS.

     ===CMD===
     STATUS
     ===END===
     ```
2. Optionally send another external from hey to the mail account.
3. Wait one tick for `RelayPollJob` to process the body command.
4. **Intermediate assertion**: `CommandResponse` with `source: "body", command: "STATUS",
   status: "pending"`, `bundle_id: nil`. `response_text` contains live vessel stats.
5. Re-arm: `Vessel.find(1).update_columns(next_dispatch_at: 1.minute.ago)`.
6. Wait for next tick — `DispatchDueVesselsJob` fires `Vessel::DispatchJob`.
7. **Final assertions**:
   - A new `Bundle` exists, `status: "sent"`.
   - `bundle_text` contains `==[ ✉ STATUS response ]==` followed by the STATUS body.
   - The pending `CommandResponse` flipped to `status: "included"`, `bundle_id == <new bundle id>`.
   - Bundle also contains the new external email digest (if step 2 done).
8. **Mailbox assertion**: sailmail receives the `HUTMAIL <date> <HH:MM>` email with both blocks.

## Scenario E — Outbound MSG + REPLY from sailor to external world

This exercises `===MSG.<ACCT> <email>===` (new outbound) and `===REPLY <hutmail_ref>===` (threaded
reply), both parsed by `Vessel#parse_and_execute_commands`, queued as `VesselReply` rows, and sent
via `OutboundMailer#send_reply` (which injects `In-Reply-To`/`References` from the linked
`MessageDigest#imap_message_id`).

Pre-requisite: at least one previously-bundled inbound message exists so you have a Hutmail ref to
reply to (e.g. `25may.AL.2` for the second R2 hey email). Inspect via console:
`MessageDigest.find(<id>).then { |m| [m.from_address, m.subject, m.imap_message_id, "25may.AL.#{m.daily_sequence}"] }`.

1. From sailmail send to `alibi@francemel.fr`:
   - Subject: anything (e.g. `E2E-LIVE-OUTBOUND`)
   - Body (plain text, markers at column 1):
     ```
     ===MSG.AL <recipient@example.com>===
     New outbound message body.
     ===END===

     ===REPLY <hutmail_ref>===
     Reply body that should thread inside the original conversation.
     ===END===
     ```
   - **Critical**: netcourrier's webmail defaults to HTML and the rich-text editor will silently
     wrap or indent markers. Either switch to "Texte simple" before composing, or inject the body
     via JS into the iframe and force `msg_type=text/plain` on submit. Verify the rendered body
     in the Sent folder before declaring the send done.
2. Wait for the next `:00 / :05 / ...` UTC tick (`RelayPollJob`).
3. **Server assertions** (Rails console):
   - `VesselReply` row per `===MSG===` block: `to_address` = recipient, `subject` = `"Hutmail message"`,
     `message_digest_id` = nil, `status` = `"sent"`, `outbound_message_id` non-nil.
   - `VesselReply` row per `===REPLY===` block: `to_address` = original sender's address,
     `subject` = `"Re: <original subject>"`, `message_digest_id` = the referenced digest's id,
     `status` = `"sent"`, `outbound_message_id` non-nil.
4. **Recipient assertions**:
   - New-message recipients see a standalone email from the mail-account's `smtp_username`. No
     `In-Reply-To` / `References` headers.
   - Reply recipient sees the email **grouped inside the original thread**. "Show original" /
     view source reveals `In-Reply-To: <imap_message_id-of-original>` and
     `References: <imap_message_id-of-original>`.
   - DKIM/SPF/DMARC pass (depends on the mail account's domain being properly configured — for
     `francemel.fr`/Mailo, all three pass).
   - Not delivered to Spam.
5. Optionally: replies the external sender now sends back to the mail-account address will be
   collected on the next dispatch tick and bundled to sailmail — effectively closing the loop
   with the sailor at sea.

## Scenario D — Mixed subject + body in one inbound

Not exercised in this execution (covered by `test/integration/scheduling_and_commands_e2e_test.rb`).
To run live: send a single email from sailmail with `Subject: PING` *and* `===CMD===\nSTATUS\n===END===`
body. Expect cr#N (subject PING, immediate) + cr#N+1 (body STATUS, deferred).

## Observability

From the dev workstation:

```bash
bin/kamal logs -f               # full stream
bin/kamal logs | grep -i "DispatchDueVesselsJob\|RelayPollJob\|Vessel::DispatchJob\|CommandResponse::DeliverJob"
bin/kamal logs | grep "vessel"  # vessel-tagged lines (current logging is thin — see below)
```

Inside the console:

```ruby
SolidQueue::Job.where("created_at >= ?", 30.minutes.ago).order(:created_at).pluck(:id, :class_name, :finished_at)
SolidQueue::RecurringExecution.order(run_at: :desc).limit(20).pluck(:task_key, :run_at)
```

> **Note**: existing log lines are sparse — `Vessel::Dispatching` only emits a single line
> on the `rescue` path. If future debugging needs more, a follow-up PR should add structured
> `Rails.logger.info` tags around `compose_next_bundle`, `parse_and_execute_subject/commands`,
> and `CommandResponse::DeliverJob#perform` (vessel id, decision, counts). Out of scope for
> this no-code-change runbook.

## Rollback

```ruby
Vessel.find(1).update_columns(
  dispatch_cadence: "manual",
  dispatch_every_hours: nil,
  last_dispatched_at: nil,
  next_dispatch_at: nil
)
```

Plus: log out of any browser sessions used (`agent-browser auth …` if needed). Test bundles
remain in DB / sent folders as audit trail — leave them.

## Troubleshooting

| Symptom | Likely cause | Action |
|---|---|---|
| Scheduler tick fired but `Bundle` count didn't change | No new mail in mail-account inbox at collect time | Confirm the inbound email landed; `MailAccount#collect_now` reads via IMAP — check the mailbox shows the message |
| Tick didn't fire at all | Solid Queue supervisor not running | `bin/kamal logs \| grep -i 'solid.queue\|recurring'`; restart with `bin/kamal app exec "bin/jobs"` (or redeploy) |
| Bundle sent but sailmail inbox empty | SMTP relay rejected, or netcourrier flagged as spam | Check `Bundle#error_message`, `Bundle#dispatch_log`; check netcourrier spam folder |
| `CommandResponse status=error` | Parser threw or downstream send failed | Inspect `cr.response_text`; check `bin/kamal logs` for backtraces around the poll tick |
| Loopback contamination (sailor's PING/PONG showing as bundled MessageDigest) | Relay polling did not mark UID processed before mail-account collection ran | Check `MailAccount#imap_move_strategy` and processed-UID tracking; this test confirmed no contamination on the shared-mailbox setup |

## Pending scenarios

Scenarios A–C and E have been run live; D is integration-test-only. The command and
collection behaviours **not yet exercised live** (notably the `GET` + screener round-trip,
budget overflow, `URGENT`/`SEND`, the error surface, and stripping/dedup) are catalogued with
step-by-step instructions in
[`e2e-live-runbook-pending-scenarios.md`](./e2e-live-runbook-pending-scenarios.md).

## Execution reports

- 2026-05-25: see [`e2e-live-runbook-execution-2026-05-25.md`](./e2e-live-runbook-execution-2026-05-25.md).

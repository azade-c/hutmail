# Live E2E — pending scenarios (catalogue)

Companion to [`e2e-live-runbook.md`](./e2e-live-runbook.md). The 2026-05-25 execution
covered scenarios **A** (scheduled bundling), **B** (subject command), **C** (deferred body
command + new external) and **E** (outbound `===MSG===`/`===REPLY===`). **D** (mixed subject +
body) is covered by the stubbed integration test but never run live.

> **Status (2026-06-03):** scenarios **F, G, H, I, J, K, M, N, O** were executed live and
> **passed** — see [`e2e-live-runbook-execution-2026-06-03.md`](./e2e-live-runbook-execution-2026-06-03.md).
> Only **L** (multi-account grouping) is still pending (needs a second IMAP mailbox).

This file lists the **command and collection behaviours the system implements but that no live
run has proven yet**, with concrete instructions for the next live session. Same conventions as
the runbook: no code changes, ephemeral DB nudges via `bin/kamal console`, assert server-side
(Rails console) **and** mailbox-side (`agent-browser`), revert at the end.

Naming continues the runbook's letters (F, G, …). Re-use the same test accounts and the
"option b" cadence trick (`update_columns(next_dispatch_at: 1.minute.ago)` to re-arm).

> **Priority order**: F and G first (the `GET` + screener round-trip is the largest untested
> feature and the whole reason the screener exists), then H/I (immediate vs deferred sends),
> then J (error surface), then the collection-quality scenarios K–O.

---

## Scenario F — `GET` screener retrieval (+ implicit wildcards) 🔴 highest priority

Proves `Vessel#parse_and_execute_commands` → `execute_get` → `find_messages_by_wildcard` →
`dispatch_get_response`. Unit-covered (`test/models/vessel_commanding_test.rb`) but never run
against real mailboxes. Needs a **screener** to exist (i.e. pending messages held back from a
bundle — see Scenario G to create one), or simply target already-bundled-then-requeued messages.

**Setup** — force a screener so some messages stay `collected`/pending:

```ruby
Vessel.find(1).update_columns(daily_budget_kb: 1, bundle_ratio: 50) # tiny budget
```

1. Send 3 external emails from `azade@hey.com` → `alibi@francemel.fr`, each ≥ ~1 KB stripped
   body, unique subjects `E2E-GET-1/2/3 <date>`. Note send order.
2. Re-arm + wait one dispatch tick. The bundle should include only what fits, and append a
   `=== SCREENER (N messages, X KB) ===` block listing the rest with their `JJmon.AL.N` refs.
3. From sailmail (`sailmailalibi@netcourrier.com`) → `alibi@francemel.fr`, **subject line**
   `GET <ref-of-a-screener-message>` (e.g. `GET 26may.AL.3`). Subject GET is answered on the
   next `RelayPollJob` tick without waiting for a dispatch tick.
4. **Server assertions**:
   - A new `Bundle` row created by `dispatch_get_response` (status `sent`), `outbound_message_id`
     present, whose `bundle_text` starts `=== HUTMAIL …` and contains the requested message in
     full, followed by a fresh `=== SCREENER …` of whatever is still pending.
   - The requested `MessageDigest` flips `collected → bundled`; others stay pending.
   - Budget is **not** checked for `GET` (soft limit) — the response sends even when the 7-day
     budget is exhausted.
5. **Wildcard variants** — repeat step 3 with each form and assert the matched set:
   - `GET 26may.AL` — every pending message of mailbox `AL` on 26 may.
   - `GET 26may` — every pending message that day, all mailboxes.
   - `GET AL` — every pending message of mailbox `AL`, any date.
   - `GET 1` — every pending message with daily sequence `1`.
   - `GET 99dec.ZZ.9` — no match → `CommandResponse`/result error, **no** bundle created,
     no email sent.
6. **Mailbox assertion**: sailmail receives the `HUTMAIL …` email; body byte-identical to the
   server `bundle_text`; the requested message body is present in full.

---

## Scenario G — Screener / budget overflow + carry-forward

Every live bundle so far carried exactly one message, so the **screener path and whole-message
budget cut were never exercised** end to end.

```ruby
Vessel.find(1).update_columns(daily_budget_kb: 1, bundle_ratio: 80)
```

1. Send 4–5 external emails large enough that only the first 1–2 fit the message budget.
2. Re-arm + wait one dispatch tick.
3. **Server assertions**:
   - `Bundle#messages_count` < total pending; `Bundle#remaining_count` = the rest.
   - `bundle_text` ends with `=== SCREENER (N messages, X KB) ===` then one
     `to_screener_line` per held message (`[ref] sender | "subject" | size`), then
     `GET <id> to download a specific message`.
   - If the screener itself overflows `screener_budget`, it is truncated with
     `... and K more messages ready for bundling`.
   - Messages whole — never cut mid-body.
   - Held messages remain bundleable (`collected`/`requeued`), **not** `bundled`.
4. **Carry-forward**: re-arm + wait the next dispatch tick *without* sending new mail. Assert the
   previously-held messages now appear as full messages in the new bundle (oldest first). Nothing
   lost.
5. Restore: `Vessel.find(1).update_columns(daily_budget_kb: 100)`.

---

## Scenario H — `URGENT` immediate send (no dispatch tick needed)

`URGENT.<ACCT>` calls `deliver_now` inside `RelayPollJob`; it must leave *before* the next
dispatch tick, unlike `SEND`/`MSG`.

1. From sailmail → `alibi@francemel.fr`, **subject line**
   `URGENT.AL azade@hey.com "Position report: 38N 28W, all well"`.
   (URGENT is one of the subject-allowed verbs — answered immediately.)
2. Wait one `RelayPollJob` tick.
3. **Server**: one `VesselReply`, `to_address=azade@hey.com`, `subject="Hutmail message"`,
   `message_digest_id=nil`, `status="sent"`, `outbound_message_id` present, `sent_at` within
   seconds of the poll tick (no waiting for a dispatch tick).
4. **Mailbox**: HEY receives the standalone message immediately; DKIM/SPF/DMARC pass.

---

## Scenario I — `SEND` via body `===CMD===` (deferred queue)

Distinguishes `SEND` (`deliver_later`) from `URGENT` (`deliver_now`) and from the `===MSG===`
block form.

1. From sailmail → `alibi@francemel.fr`, body:
   ```
   ===CMD===
   SEND.AL azade@hey.com "Routine note from the boat"
   ===END===
   ```
2. Wait one `RelayPollJob` tick.
3. **Server**: `VesselReply` created `status="pending"`, then delivered by its
   `VesselReply::DeliverJob` shortly after (enqueued, not inline). Confirm it ends `status="sent"`.
4. **Mailbox**: HEY receives it. Compare wall-clock send latency vs Scenario H (URGENT should be
   inline-fast; SEND goes through the queue).

---

## Scenario J — Error surface reaches the sailor

The parser emits structured error results and, for unknown commands, an error
`CommandResponse`. None of these error paths were verified to actually reach sailmail.

For each, send from sailmail and assert the sailor receives an intelligible error (subject form
answered immediately; body form folded into the next bundle as a `==[ ✉ … response ]==` block):

| Input | Expected |
|---|---|
| Subject `FOOBAR` | rejected as non-allowed subject verb → **no** response (silent), `results == []` |
| Body `===CMD===\nFOOBAR\n===END===` | `CommandResponse source=body`, text `ERR: unknown command "FOOBAR"`, folded into next bundle |
| Body `===REPLY 99dec.ZZ.9===\n…\n===END===` | result error `Unknown hutmail_id`, **no** `VesselReply` |
| Body `===MSG.ZZ x@y.com===\n…\n===END===` | result error `Unknown account short_code: ZZ`, no `VesselReply` |
| Subject `GET 99dec.ZZ.9` | result error `No matching messages`, no bundle |

Confirm server-side `results`/`CommandResponse` rows **and** that the body-command error block
appears in the next dispatched bundle's `bundle_text`.

---

## Scenario K — Subject `STATUS` and `HELP` (only `PING` was run live)

1. Subject `STATUS` → immediate `CommandResponse source=subject command=STATUS status=sent`;
   sailmail receives subject `HUTMAIL STATUS`, body with `ready: N messages`,
   `budget: … remaining (7d)`, `last dispatch`, `next dispatch (<cadence>)`.
2. Subject `HELP` → immediate; sailmail receives the `HUTMAIL commands` cheat-sheet.
3. Subject `Re: Fwd: STATUS` → prefixes stripped, still answered (proves the `Re:/Fwd:` cleanup).

---

## Scenario L — Multi-account grouping + per-mailbox sequence

The test vessel has a single mail account (`AL`). Bundle grouping `==[ XX — name (user) ]==`
and **per-mailbox** daily sequence numbering are therefore untested live.

1. Add a second mail account to `Vessel#1` (e.g. `azade@hey.com` as an IMAP/SMTP account with
   `short_code: "HY"`) via the web UI or console, so both IMAP creds verify.
2. Send mail into both inboxes the same day; re-arm + dispatch.
3. **Assert**: `bundle_text` has two `==[ AL — … ]==` and `==[ HY — … ]==` sections; refs are
   `JJmon.AL.1` and `JJmon.HY.1` (sequence resets per mailbox per day, not globally).
4. Remove the temporary account afterwards.

---

## Scenario M — Stripping fidelity on real mail

Collection-side quality, only spot-checked so far.

1. Send one HTML newsletter-style email **with** an inline image, a `-- ` signature, a mobile
   sig (`Envoyé de mon iPhone`), and a quoted reply (`Le … a écrit :`).
2. Send one email with a real **attachment** (e.g. a small PDF).
3. Dispatch and inspect the bundled `MessageDigest`:
   - `stripped_body`: HTML→text, signature/quote/disclaimer removed, standalone URLs gone.
   - Inline image → placeholder kept in body position; attachment → `📎 file.pdf (NNN KB)`
     line, **not** the bytes. `attachments_metadata` JSON populated.
   - `to_radio_text` in `bundle_text` shows the placeholder, never base64.

---

## Scenario N — `skip_already_read` + Message-ID dedup

DB-as-source-of-truth guarantees, untested live.

1. With `skip_already_read=true` (default): send an email, **read it in webmail before the next
   dispatch tick**. Assert it is **not** collected (no `MessageDigest`).
2. Send another email, leave it unread → collected normally.
3. Re-run collection (re-arm + tick) without new mail → **no duplicate** `MessageDigest` for the
   same `imap_message_id`; toggling the IMAP read flag must not cause re-collection.
4. Optionally flip `skip_already_read=false` on the account and confirm already-read mail *is*
   then collected.

---

## Scenario O — IMAP courtesy: Seen + archive after send

After a bundle sends, `mark_sources_processed` should mark sources `\Seen` and MOVE/COPY them to
the `Hutmail` folder (capability-dependent).

1. After any dispatch, inspect `alibi@francemel.fr` in webmail: bundled messages marked read and
   relocated to the `Hutmail` folder (or `Hutmail/<vessel>` per `RelayAccount::PROCESSED_FOLDER`).
2. Check `Bundle#dispatch_log` shows `IMAP MOVE → Hutmail/` (or `COPY+DELETE+EXPUNGE` fallback).
3. Confirm the archived message is **not** re-collected on the next tick (DB dedup + it left INBOX).

---

## Known non-testable today (document, don't chase)

- **`PAUSE` / `RESUME`** — currently acknowledged-only stubs (`vessel_paused?` always `false`);
  they return `:ok` but do **not** actually suspend collection. A live test would show no
  behavioural change. Mark as a code gap, not a test gap, until implemented.
- **`WHITELIST` / `BLACKLIST`** — same: acknowledged, no persistence/filtering yet.
- **`DROP`** — referenced in the spec but **not implemented** (`execute_command` has no `DROP`
  branch); it currently returns `unknown command`. Don't write a live scenario until built.

When any of the above ships, move it out of this list into a numbered scenario.

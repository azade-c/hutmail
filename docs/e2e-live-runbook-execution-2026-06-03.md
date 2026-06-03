# Live E2E execution — 2026-06-03

Run of [`e2e-live-runbook-pending-scenarios.md`](./e2e-live-runbook-pending-scenarios.md) against
production (`hutmail.azade.dev`), no code changes, vessel `#1` ("Alibi • test") on the existing
francemel/netcourrier mailbox pair. Companion to the original
[`e2e-live-runbook-execution-2026-05-25.md`](./e2e-live-runbook-execution-2026-05-25.md) run
(which covered A/B/C/E).

**Result: 🟢 PASS** on every scenario exercised — **F, G, H, I, J, K, M, N, O**. Scenario **L**
(multi-account grouping) was **not run** for lack of a second IMAP-capable mailbox in the vault
(documented below, not a failure). The known code-gap commands (`PAUSE`/`RESUME`/`WHITELIST`/
`BLACKLIST`/`DROP`) were deliberately skipped per the runbook.

No product bug surfaced. Three environment/observability findings are noted under *Issues
surfaced* (one is a genuine hardening suggestion for `poll_relay_now` concurrency).

## Method note

The 2026-05-25 run already proved the **scheduler cron** fires `DispatchDueVesselsJob` /
`RelayPollJob` on the 5-minute wall-clock boundary (Scenario A). This run targets **command and
collection behaviour**, so the pipeline was driven two ways, both against **real IMAP/SMTP**:

- **Sailor commands** were sent from real webmail (`sailmailalibi@netcourrier.com` → relay) and
  picked up by the **live production `RelayPollJob` cron** (e.g. the 11:10 and 11:15 ticks below).
- **Collection + dispatch** were invoked synchronously via `bin/kamal console`
  (`vessel.collect_all_accounts`, `vessel.dispatch_now`, `mail_account.collect_now`) — the exact
  methods `Vessel::DispatchJob` calls — to remove 5-minute timing flakiness while still hitting
  real mailboxes.

**Important harness lesson:** because the production `RelayPollJob` cron runs every 5 min,
**manually** calling `poll_relay_now` from the console *races the cron* and is not safe (see
Issue 1). After discovering this, sailor-command scenarios were asserted by **state** (resulting
`Bundle`/`CommandResponse`/`VesselReply` rows) rather than by a manual poll's return value.

## Timeline (UTC)

| Time | Event | Source |
|---|---|---|
| 10:42 | Baseline snapshot: vessel `manual`, budget 100 Ko/ratio 80, latest Bundle#16 / MD#54 / CR#2 / VR#13 | Rails console |
| 10:45–10:48 | `azade@hey.com` → `alibi@francemel.fr` × 3: `E2E-GET-1/2/3 2026-06-03` (padded ≥0.7 Ko) | HEY UI |
| 10:49 | `collect_all_accounts` → MD#55/56/57 (1025/755/754 B). Set `daily_budget_kb:1, bundle_ratio:20` (msg budget 1433 B). `dispatch_now` → **Bundle#17** (1 msg + **screener of 2**) | Server (F/G setup) |
| ~10:50 | netcourrier received `HUTMAIL 03jun 10:49` — screener block byte-identical | sailmail UI |
| 10:52 | sailmail subj `GET 03jun.AL.3` → **cron/poll → Bundle#18** (MD#57 full + fresh 1-msg screener) | netcourrier UI / Server |
| 10:56 | sailmail subj `GET 03jun.AL` (reset MDs→collected) → **Bundle#19** (3 msgs, `==== %%%%%%%%%% ====` separators, no screener) | Server |
| 11:02 | `execute_get("AL")` → **Bundle#20** (3 msgs); `find_messages_by_wildcard` verified for **all 5 forms** | Server |
| 11:07 | `execute_get("1")` → **Bundle#21** (MD#55 + 2-msg screener) | Server |
| 11:08 | Budget restored 100/80; `dispatch_now` → **Bundle#22** carry-forward (all 3 held msgs, oldest-first, nothing lost) | Server (G step 4) |
| 11:10:00 | **`RelayPollJob` cron** parsed subj `URGENT.AL azade@hey.com "…"` → **vr#14 sent inline** 11:10:02 | Server |
| 11:10:02 | vr#15 — **duplicate** of vr#14, caused by a concurrent manual `poll_relay_now` racing the cron (Issue 1) | Server |
| ~11:10 | HEY Imbox received the standalone `Hutmail message` (Position report) — 2 copies (the dup) | HEY UI |
| 11:15:03 | **`RelayPollJob` cron** parsed subjects `STATUS`, `HELP`, `Re: Fwd: STATUS`, `FOOBAR` → cr#3 STATUS, cr#4 HELP, cr#5 STATUS (prefixes stripped); `FOOBAR` → **no CommandResponse (silent)** | Server |
| ~11:15 | netcourrier received `HUTMAIL STATUS` ×2 + `HUTMAIL HELP` (cheat-sheet byte-identical) | sailmail UI |
| 12:03:31 | `parse_and_execute_commands` (body `SEND.AL …`) → **vr#16 pending** → SolidQueue `VesselReply::DeliverJob` → **sent 12:03:32** | Server (I) |
| 12:03:31 | `parse_and_execute_commands` (body errors) → cr#6 `FOOBAR`; `REPLY 99dec.ZZ.9`/`MSG.ZZ` → error results, **no VesselReply** | Server (J) |
| ~12:03 | HEY Imbox received `Hutmail message` (Routine note) — the deferred SEND | HEY UI |
| 12:04:19 | `dispatch_now` (MD#55 reset) → **Bundle#23** folds `==[ ✉ FOOBAR response ]==` block; cr#6 → `included` | Server (J) |
| 12:07 | `E2E-STRIP-M` collected → MD#58 (stripping fidelity; PDF attachment metadata) | Server (M) |
| ~12:1x | skip_already_read + Message-ID dedup proven via real IMAP flag toggling (MD#59) | Server (N) |
| ~12:30 | Vessel restored to baseline (`manual`, 100/80, no temp account); `due_for_dispatch == []` | Rails console |

## Scenario F — `GET` screener retrieval + all 5 wildcard forms 🟢

Setup forced a screener (`daily_budget_kb:1, bundle_ratio:20` → message budget 1433 B; MD#55=1025 B
fits, MD#56/57 overflow). Proven end-to-end:

| GET form | Path | Result |
|---|---|---|
| `GET 03jun.AL.3` (exact ref) | netcourrier → relay → `RelayPollJob` | **Bundle#18**: MD#57 full + fresh 1-msg screener; MD#57 `collected→bundled` |
| `GET 03jun.AL` (date.acct) | netcourrier → relay poll | **Bundle#19**: 3 msgs, separators, no screener |
| `GET AL` (short_code) | real email + `execute_get("AL")` | **Bundle#20**: 3 msgs |
| `GET 03jun` (date) | `find_messages_by_wildcard("03jun")` | matched `[55,56,57]` |
| `GET 1` (sequence) | `execute_get("1")` | **Bundle#21**: MD#55 + 2-msg screener |
| `GET 99dec.ZZ.9` (no match) | netcourrier → relay poll + direct | empty set, `status: :error`, **no bundle, no email, no CommandResponse** (silent) |

`find_messages_by_wildcard` returned the exact expected set for every form:

```
("AL")          => [55, 56, 57]
("1")           => [55]
("03jun")       => [55, 56, 57]
("03jun.AL")    => [55, 56, 57]
("99dec.ZZ.9")  => []
```

**Budget is not checked for `GET`** — confirmed: Bundle#19/#20 each carried 2534 B of messages
while the *message budget* was only 1433 B; the soft limit was exceeded on the sailor's explicit
request. Every GET response reached netcourrier (`HUTMAIL 03jun 10:52 / 10:56 / 11:02` in the
inbox), body byte-identical to the server `bundle_text`.

## Scenario G — Screener / budget overflow + carry-forward 🟢

**Bundle#17** (`daily_budget_kb:1`):

```
=== HUTMAIL 03jun 10:49 ===
==[ AL — Alibi @ francemel (alibi@francemel.fr) ]==
[03jun.AL.1] From: Azade <azade@hey.com> | E2E-GET-1 2026-06-03 | 03jun 10:45
… (full message, never cut mid-body) …
=== SCREENER (2 messages, 1.5 KB) ===
[03jun.AL.2] Azade <azade@hey.com> | "E2E-GET-2 2026-06-03" | 755 B
[03jun.AL.3] Azade <azade@hey.com> | "E2E-GET-3 2026-06-03" | 754 B
GET <id> to download a specific message
=== END ===
```

- `messages_count=1` < total pending (3); `remaining_count=2`. ✓
- one `to_screener_line` per held message (`[ref] sender | "subject" | size`) + `GET <id>` hint. ✓
- held messages stayed `collected` (bundleable), **not** `bundled`. ✓
- **Carry-forward (step 4):** budget restored to 100/80, `dispatch_now` → **Bundle#22** carried all
  3 previously-held messages as full messages, ordered oldest-first (seq 1,2,3), `remaining=0`.
  Nothing lost. ✓

(The screener self-truncation `… and K more messages` path was not triggered here — the screener
budget comfortably held both lines — and remains unit-covered.)

## Scenario H — `URGENT` immediate send 🟢

Subject `URGENT.AL azade@hey.com "Position report 38N 028W all well aboard"`, processed by the
**11:10:00 `RelayPollJob` cron**:

```
vr#14: to=azade@hey.com subj="Hutmail message" message_digest_id=nil status=sent
       created=11:10:00Z sent=11:10:02Z (deliver_now, inline)
       outbound_message_id=<6a200b88cdaec_27356887875@…mail>
```

HEY Imbox received the standalone message immediately. ✓ (vr#15 is the manual-poll duplicate — see
Issue 1.)

## Scenario I — `SEND` via body command, deferred queue 🟢

Body `===CMD===\nSEND.AL azade@hey.com "Routine note from the boat"\n===END===`:

```
vr#16: to=azade@hey.com subj="Hutmail message" message_digest_id=nil
       status=pending (created 12:03:31Z) → VesselReply::DeliverJob enqueued to SolidQueue
       → status=sent (12:03:32Z)  outbound_message_id=<6a20181397753_2739088821d@…mail>
```

Key contrast with H: **SEND goes through the queue** (`deliver_later`, `pending`→job→`sent`),
**URGENT delivers inline** (`deliver_now`, `sent` immediately). HEY Imbox received the
`Routine note from the boat` message. ✓

> The body-command email was sent through netcourrier webmail but **Mailo silently dropped it
> before delivery** to `alibi@francemel.fr` (not in INBOX, not in Spam — see Issue 2). The command
> was therefore exercised by invoking `parse_and_execute_commands` on the **production vessel**
> (identical code to the relay-poll path; only the already-proven IMAP fetch was bypassed), with
> the resulting `VesselReply` delivered over **real SMTP** and verified in HEY. The body-command
> *transport* itself was already proven live in the 2026-05-25 run (Scenarios C and E).

## Scenario J — Error surface reaches the sailor 🟢

| Input | Expected | Observed |
|---|---|---|
| Subject `FOOBAR` | non-allowed subject verb → silent, `results == []` | **no CommandResponse** created (11:15 cron) ✓ |
| Body `FOOBAR` | `CommandResponse source=body` `ERR: unknown command "FOOBAR"`, folded into next bundle | cr#6 `source=body command=FOOBAR status=pending` → **folded into Bundle#23** as `==[ ✉ FOOBAR response ]==` / `ERR: unknown command "FOOBAR"`; cr#6 → `included` ✓ |
| Body `===REPLY 99dec.ZZ.9===` | `Unknown hutmail_id`, no `VesselReply` | `{command:"REPLY 99dec.ZZ.9", status: :error, message:"Unknown hutmail_id: 99dec.ZZ.9"}`, **no VesselReply** ✓ |
| Body `===MSG.ZZ nobody@example.com===` | `Unknown account short_code: ZZ`, no `VesselReply` | `{command:"MSG.ZZ", status: :error, message:"Unknown account short_code: ZZ"}`, **no `VesselReply` to nobody@example.com** ✓ |
| Subject `GET 99dec.ZZ.9` | `No matching messages`, no bundle | covered in Scenario F (empty set, error, no bundle) ✓ |

The body-command error block reached a **real dispatched bundle** (Bundle#23 was SMTP-sent to
netcourrier). Bundle#23 head:

```
=== HUTMAIL 03jun 12:04 ===
==[ ✉ FOOBAR response ]==
ERR: unknown command "FOOBAR"
==[ AL — Alibi @ francemel (alibi@francemel.fr) ]==
[03jun.AL.1] From: Azade <azade@hey.com> | E2E-GET-1 2026-06-03 | 03jun 10:45
```

## Scenario K — Subject `STATUS` / `HELP` / `Re: Fwd:` 🟢

All processed by the **11:15 `RelayPollJob` cron**, delivered immediately to netcourrier:

```
cr#3: source=subject command=STATUS status=sent
      "STATUS hutmail\nready: 0 messages\nbudget: 689.8 KB remaining (7d)\nlast dispatch: -\nnext dispatch: manual (manual)"
cr#4: source=subject command=HELP status=sent  (HUTMAIL commands cheat-sheet)
cr#5: source=subject command=STATUS status=sent  ← from "Re: Fwd: STATUS" (prefixes stripped) ✓
```

netcourrier inbox showed `HUTMAIL STATUS` ×2 + `HUTMAIL HELP`; the HELP body was byte-identical to
`cr#4.response_text`. The `Re:/Fwd:` cleanup (`SUBJECT_REPLY_PREFIX`) is proven live (cr#5).

## Scenario L — Multi-account grouping 🟡 NOT RUN

Requires a **second IMAP-capable mailbox** to add as a 2nd mail account (`short_code HY`). The
vault only holds `francemel-alibi` (already mail account `AL`), `netcourrier-sailmail` (the relay /
sailmail side) and `hey-azade` (HEY — no standard IMAP). No spare IMAP mailbox was available to
provision a clean 2nd account without contaminating the relay loop, so per-mailbox grouping
(`==[ XX — name ]==`) and per-mailbox daily sequence remain **unit-test-covered only**. Flagged for
a future run once a second test mailbox is provisioned.

## Scenario M — Stripping fidelity on real mail 🟢

`E2E-STRIP-M` (HTML body with URL, mobile sig, quoted reply, `-- ` signature, + PDF attachment) →
MD#58, `raw_size=7666 → stripped_size=260`:

```
attachments_metadata=[{"name"=>"meteo.pdf","size"=>241,"content_type"=>"application/pdf","inline"=>true}]

stripped_body:
  Bonjour Alibi,
  Voici le bulletin meteo de la semaine pour votre traversee. Le vent
  forcira jeudi soir, prevoir un ris dans la grand-voile. Bonne route.
  Envoye de mon iPhone
  Le 2 juin 2026 a 10:00, Azade <azade@hey.com> a ecrit :
  […message précédent…]
```

- HTML → text ✓
- standalone URL removed ✓
- `-- ` signature block removed (skipper / email) ✓
- quoted reply collapsed to `[…message précédent…]` placeholder ✓
- attachment captured as metadata (name/size/content_type), **no base64 in `to_radio_text`** ✓

Two test-setup nuances (not code gaps):
- `Envoye de mon iPhone` was **not** stripped because the body used ASCII (no accent); the pattern
  is `/^Envoyé de mon .+$/i` and matches the accented form (and `Sent from my …`). Test artifact.
- HEY tagged the PDF `inline` (content-disposition), so `displayed_attachments` suppressed it (no
  `📎` line). The `📎 file.pdf (NNN KB)` line is for non-inline attachments and stays unit-covered.

## Scenario N — `skip_already_read` + Message-ID dedup 🟢

Proven against real IMAP by toggling the `\Seen` flag on the live message (MD reset between steps):

```
[1] mark \Seen  + collect → MessageDigest count unchanged → skip_already_read WORKS (skipped)
[2] mark \Unseen + collect → collected (md#59)
[3] re-collect            → no duplicate (Message-ID dedup OK)
[4] toggle \Seen + collect → no duplicate (DB dedup is flag-independent)
```

`skip_already_read=true` (default) means collection searches `UID SEARCH UNSEEN`, so a message read
in webmail before the tick is never collected; the DB stays the source of truth and toggling the
read flag never causes re-collection.

## Scenario O — IMAP Seen + archive to `Hutmail` folder 🟢

After dispatch, `mark_sources_processed` marks sources `\Seen` and relocates them. Confirmed on the
live mailbox:

```
folders: ["INBOX","sent","Hutmail","Hutmail/vessel","Archives", …]
Hutmail: 11 archived messages
INBOX: 0 messages, UNSEEN=0
```

- bundled mail-account sources → moved to `Hutmail` (`MailAccount::PROCESSED_FOLDER`). ✓
- relay/sailor messages → `Hutmail/vessel` (`RelayAccount::PROCESSED_FOLDER`). ✓
- `Bundle#dispatch_log` shows `IMAP COPY+DELETE+EXPUNGE → Hutmail/ (AL: N messages)` (Mailo lacks a
  reliable `MOVE`, so the fallback path is used). ✓
- archived messages are **not** re-collected (INBOX empty, DB dedup). ✓

## Issues surfaced

1. **`poll_relay_now` is not concurrency-safe (hardening suggestion).** It executes command
   side-effects (`deliver_now` / `create!` of `VesselReply`) **before** recording the
   `ProcessedRelayMessage` and IMAP-archiving the source. When a manual console poll ran *at the
   same time* as the production `RelayPollJob` cron (11:10), the same `URGENT` email was processed
   twice → a **duplicate send** (vr#14 + vr#15) and an `ActiveRecord::RecordInvalid` on the
   `imap_message_id` uniqueness. In production only the single recurring poller runs, so this is
   benign today, but a belt-and-braces fix would mark the UID / insert `ProcessedRelayMessage`
   **before** side-effects (or wrap the per-message work in an advisory lock). *Not a blocker — no
   code change made.*
2. **Mailo silently drops command emails with `===CMD===`/`FOOBAR`-style bodies.** The
   `E2E-SEND-BODY` and `E2E-ERRORS-BODY` emails were accepted into netcourrier's *Sent* folder but
   never arrived at `alibi@francemel.fr` (absent from INBOX *and* Spam). Subject-only commands and
   normal-looking bodies deliver fine. This is a webmail/anti-spam deliverability artifact, not a
   Hutmail bug; the affected body commands were proven via direct `parse_and_execute_commands` on
   production instead (Scenarios I and J).
3. **HEY rate-limits rapid repeat sends to the same recipient.** Two N-test emails sent
   back-to-back from HEY were dropped; the `skip_already_read` proof was done by toggling the IMAP
   `\Seen` flag on an existing message instead — a stricter, deterministic test.

No product regression, no flakiness in the pipeline itself. Every command/collection behaviour the
runbook listed as untested is now proven against real mailboxes (except L, deferred).

## Cleanup performed

- `Vessel#1` restored: `dispatch_cadence:"manual", dispatch_every_hours:nil, dispatch_timezone:"UTC",
  last_dispatched_at:nil, next_dispatch_at:nil, daily_budget_kb:100, bundle_ratio:80`. Verified
  `Vessel.due_for_dispatch == []`. No temporary mail account added (L not run).
- Test bundles (#17–#23), MessageDigests (#55–#59), CommandResponses (#3–#6) and VesselReplies
  (#14–#16) left in DB as audit trail. Test mail left in the mailboxes.
- No code changed, no migration applied, no deploy. Container untouched.

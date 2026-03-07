# HutMail 🦫

> The beaver lodge — where mail is sorted and stored.

## Context

Sailors ("the Beavers") are embarking on an around-the-world sailing trip for ~18 months. Their only link to the outside world: an SSB radio (Single Side Band) via the **SailMail** network, with a backup **Iridium** satellite phone.

### Bandwidth constraints

- **SSB/SailMail**: 90 min / 7 rolling days, PACTOR protocol (built-in Huffman compression)
- **Throughput**: 0.1 to 0.6 KB/s on average
- **Estimated budget**: ~200 KB/day total, of which **~100 KB/day for email** (the rest = weather, GRIB files, etc.)
- **Iridium**: ~400 kbps but €1.5/min (backup only)
- **Airmail**: Windows software on the boat, no IMAP filtering — everything that arrives gets downloaded

### Radio budget

The budget is not a hard quota but a calculation based on airtime:
- **90 minutes per 7 rolling days** (imposed by SailMail)
- At 0.1–0.6 KB/s, that yields **~540 KB to ~3.2 MB per week** depending on conditions
- In practice, we budget **100 KB/day for email** (conservative estimate)
- HutMail tracks consumed budget over **7 rolling days** and adapts its sends

### The problem

No filtering on the boat side: a single spam or large email can exhaust the radio credit. We need a "shore-side postman" who filters, aggregates, and transmits intelligently.

## Solution: HutMail

A **Ruby on Rails** application that acts as an automated shore-side postman.

### Architecture

```
[Beavers' mailboxes]                [Outside world]
        |          ^                      |          ^
        v          |                      v          |
   IMAP (fetch)  SMTP (reply)          SMTP       SMTP
        |          |                      |          |
        v          |                      v          |
  +------------------------------------------------------+
  |                  HutMail (Rails)                      |
  |                                                       |
  |  - Multi-account aggregation (IMAP+SMTP)             |
  |  - Aggressive stripping                               |
  |  - Bundling with radio budget management             |
  |  - Database = source of truth                        |
  |  - Email CLI (commands)                               |
  +------------------------------------------------------+
        |                    ^
        v                    |
     SMTP (relay)      IMAP (relay)
        |                    |
        v                    |
  [HutMail relay account: hutmail-relay@example.com]
        |                    ^
        v                    |
     SMTP                  SMTP
        |                    |
        v                    |
  [SailMail: CALLSIGN@sailmail.com]
        |                    ^
        | PACTOR (radio)     |
        v                    |
  [Boat - Airmail]    ------+
```

### Relay account (SailMail bridge)

HutMail communicates with the boat via a **relay account** — a regular email address that serves as a bridge to SailMail:

- **Boat's SailMail address**: `CALLSIGN@sailmail.com` — the address HutMail sends bundles to
- **HutMail relay account**: a standard email account (e.g. `hutmail-relay@gmail.com`) configured with IMAP+SMTP, which:
  - **Sends** bundles to the SailMail address
  - **Receives** replies and commands from the boat (the boat replies to this address)

The relay account is configured at the user level (not per monitored mail account). It is the sole communication channel with the boat.

**Configuration:**
| Field | Description |
|-------|-------------|
| sailmail_address | Boat's SailMail address (`CALLSIGN@sailmail.com`) |
| relay_imap_server | Relay account IMAP server |
| relay_imap_port | IMAP port |
| relay_imap_username | IMAP username |
| relay_imap_password | IMAP password (encrypted) |
| relay_imap_use_ssl | SSL yes/no |
| relay_smtp_server | Relay account SMTP server |
| relay_smtp_port | SMTP port |
| relay_smtp_username | SMTP username |
| relay_smtp_password | SMTP password (encrypted) |
| relay_smtp_use_starttls | STARTTLS yes/no |

**Flow:**
1. HutMail sends a bundle via relay SMTP → `CALLSIGN@sailmail.com`
2. The boat receives the bundle via radio in Airmail
3. The boat replies to the relay address (`hutmail-relay@gmail.com`)
4. HutMail polls the relay via IMAP to receive replies and commands
5. HutMail processes commands / dispatches replies

### Mail accounts (IMAP + SMTP)

Each **monitored** mail account in HutMail has **two sides**:

- **Receiving (IMAP)**: server, port, credentials, SSL — to collect incoming messages
- **Sending (SMTP)**: server, port, credentials, SSL/STARTTLS — to send boat replies from the correct account

When adding an account, **both configurations are verified**:
1. IMAP connection tested (login + INBOX access)
2. SMTP connection tested (login + EHLO)

The account is only saved if both tests pass.

### Handling already-read emails

When the crew has internet access (port of call, marina wifi), they can read their emails directly on their phone or laptop. HutMail handles this situation:

- **Per-account option**: `skip_already_read` (boolean, default: `true`)
  - If `true`: during collection, messages already marked as read in IMAP are skipped (the crew already read them with an internet connection — no need to resend via radio)
  - If `false`: all messages are collected regardless of read status (useful if the crew wants a complete archive via SailMail)
- This IMAP flag is used only as an **input signal** during collection ("has the user already read this email?"), not as a tracking mechanism
- The database remains the source of truth for tracking known and sent messages

**Scenarios:**
| Situation | `skip_already_read=true` | `skip_already_read=false` |
|-----------|--------------------------|---------------------------|
| Email arrives, nobody reads it | Collected ✅ | Collected ✅ |
| Email read on phone at marina | Skipped (already read) | Collected anyway ✅ |
| Email sent via HutMail, then read at marina | Already in DB, skipped | Already in DB, skipped |
| PAUSE command active | No collection | No collection |

### Message identifiers

Each collected message receives a **stable identifier** based on its reception date and source mailbox, human-readable and usable in commands:

```
01mar.GM.1    — 1st message of March 1st, mailbox "GM" (Gmail)
01mar.OR.2    — 2nd message of March 1st, mailbox "OR" (Orange)
28feb.GM.1    — message from February 28th, mailbox "GM"
15jan26.GM.3  — 3rd message from January 15th 2026, explicit year
```

Rules:
- Format: `DDmon.BB.N` (zero-padded day + first 3 letters of month in English + `.` + 2-letter mailbox code + `.` + per-mailbox daily sequence number)
- The **mailbox code** (2 uppercase letters) is defined by the user when creating a `mail_account` (e.g.: `GM` for Gmail, `OR` for Orange, `WK` for Work). Stored as `short_code` on the `mail_accounts` table.
- The sequence number N is **per mailbox per day** (not global)
- Day is zero-padded: `01mar`, `09feb`, `28feb`
- Year is omitted by default (current year). If the year differs, it's appended: `15jan26.GM.3`
- The identifier is assigned at collection and remains stable (never changes, even if new messages arrive)
- Allows the boat to reference a specific message in commands: `DROP 01mar.GM.2` or `GET 28feb.OR.1`

## Data model

The HutMail database is the **single source of truth**. We never rely on IMAP read/unread status to determine what has been collected or sent. The IMAP `\Seen` flag is used only:
1. As an **input signal** during collection (`skip_already_read` option)
2. As a **courtesy marking** after sending

### Tables

#### `users`
| Field | Type | Description |
|-------|------|-------------|
| id | integer | PK |
| email_address | string | HutMail login |
| password_digest | string | bcrypt |
| sailmail_address | string | Boat's SailMail address (`CALLSIGN@sailmail.com`) |
| relay_imap_server | string | Relay IMAP server |
| relay_imap_port | integer | Relay IMAP port |
| relay_imap_username | string | |
| relay_imap_password | string | Encrypted |
| relay_imap_use_ssl | boolean | |
| relay_smtp_server | string | Relay SMTP server |
| relay_smtp_port | integer | Relay SMTP port |
| relay_smtp_username | string | |
| relay_smtp_password | string | Encrypted |
| relay_smtp_use_starttls | boolean | |
| bundle_ratio | integer | Percentage of budget for full messages (default: 80). The remaining % is reserved for the screener. |
| daily_budget_kb | integer | Daily email budget in KB (default: 100). Soft limit — the skipper can exceed it via GET. |

#### `mail_accounts`
| Field | Type | Description |
|-------|------|-------------|
| id | integer | PK |
| user_id | integer | FK → users |
| name | string | Display name ("Personal Gmail") |
| short_code | string | 2-letter uppercase code for hutmail_id (e.g.: `GM`, `OR`). Unique per user. |
| imap_server | string | e.g.: imap.gmail.com |
| imap_port | integer | e.g.: 993 |
| imap_username | string | |
| imap_password | string | Encrypted (Active Record Encryption) |
| imap_use_ssl | boolean | |
| smtp_server | string | e.g.: smtp.gmail.com |
| smtp_port | integer | e.g.: 587 |
| smtp_username | string | |
| smtp_password | string | Encrypted |
| smtp_use_starttls | boolean | |
| is_default | boolean | Default account for sends with no matching sender |
| skip_already_read | boolean | Skip messages already read in IMAP (default: true) |

#### `collected_messages`
Source of truth for all messages known to HutMail. A message is added here at collection and is never re-collected as long as it exists.

| Field | Type | Description |
|-------|------|-------------|
| id | integer | PK |
| mail_account_id | integer | FK → mail_accounts |
| hutmail_id | string | Stable identifier (`01mar.GM.1`), unique |
| imap_uid | integer | IMAP UID of the message on the source server |
| imap_message_id | string | `Message-ID` email header (for deduplication) |
| from_address | string | Sender |
| from_name | string | Sender display name |
| to_address | string | Recipient |
| subject | string | Original subject |
| date | datetime | Original message date |
| raw_size | integer | Raw size (bytes) |
| stripped_body | text | Body after stripping |
| stripped_size | integer | Size after stripping (bytes) |
| status | string | `pending` → `sent` / `dropped` |
| collected_at | datetime | Date collected by HutMail |
| sent_at | datetime | Date sent to boat (null if not yet sent) |
| bundle_id | integer | FK → bundles (null if not yet bundled) |

**Statuses:**
- `pending`: collected, awaiting inclusion in a bundle
- `sent`: successfully sent to the boat
- `dropped`: excluded by the boat (via `DROP` command) or by a rule

**Deduplication:** during collection, HutMail checks if the `imap_message_id` already exists for this `mail_account_id`. If so, the message is skipped. This prevents re-collecting a message even if the IMAP state changes (read/unread manipulated by another client).

#### `bundles`
| Field | Type | Description |
|-------|------|-------------|
| id | integer | PK |
| user_id | integer | FK → users |
| sent_at | datetime | Send date |
| total_raw_size | integer | Total raw size of included messages |
| total_stripped_size | integer | Total stripped size |
| bundle_text | text | Full text of the sent bundle |
| status | string | `draft` → `sent` → `error` |
| error_message | string | If send error |
| messages_count | integer | Number of included messages |
| remaining_count | integer | Number of messages in summary (not included) |

#### `boat_replies`
| Field | Type | Description |
|-------|------|-------------|
| id | integer | PK |
| user_id | integer | FK → users |
| mail_account_id | integer | FK → mail_accounts (SMTP account used) |
| in_reply_to_id | integer | FK → collected_messages (nullable) |
| to_address | string | Final recipient |
| body | text | Reply body |
| sent_at | datetime | Send date |
| status | string | `pending` → `sent` → `error` |
| error_message | string | If error |

#### ~~`budget_entries`~~ (removed)
Budget is calculated directly from `bundles` (`total_stripped_size` + `sent_at`) over 7 rolling days. No separate table needed.

### Collection flow (detailed)

```
For each mail_account of the user:
  1. Connect to IMAP
  2. List messages in INBOX:
     - If skip_already_read = true: SEARCH UNSEEN
     - If skip_already_read = false: SEARCH ALL
  3. For each message:
     a. Extract the Message-ID (header)
     b. Check in database: SELECT FROM collected_messages
        WHERE mail_account_id = X AND imap_message_id = Y
     c. If found → SKIP (already known)
     d. If not found → collect:
        - Download complete message (RFC822)
        - Parse with the Mail gem
        - Strip the body
        - Assign a hutmail_id (01mar.GM.1, 01mar.GM.2, etc.)
        - INSERT into collected_messages with status = 'pending'
  4. Disconnect from IMAP
```

The database determines whether a message is already known (deduplication by `Message-ID`). The IMAP read/unread flag is used only as a pre-selection filter when `skip_already_read` is enabled.

**After sending a bundle**, HutMail marks messages as read in IMAP **as a courtesy** (so the mailbox looks clean in regular mail clients), but this is not used as a source of truth.

### Boat reception flow (detailed)

```
Cron or regular polling:
  1. Connect to relay account via IMAP
  2. Search for unread messages FROM sailmail_address
  3. For each message:
     a. Parse the content
     b. If contains ===CMD=== → process commands
     c. If contains ===MSG=== → dispatch replies:
        - For each ===MSG recipient=== block:
          - Find the appropriate mail_account (via collected_messages or is_default)
          - Send via mail_account's SMTP
          - Record in boat_replies
     d. Mark the relay message as read
  4. Disconnect from IMAP
```

### Inbound flow (world → boat)

#### Principle: send within the budget, stripped to the max

All messages from all configured IMAP accounts are collected and stripped. HutMail sends as much as the radio budget allows. If everything doesn't fit, the rest is queued with a summary sent to the boat.

#### Step 1: Collection

1. Cron fetches the Beavers' IMAP mailboxes at regular intervals
2. Multiple IMAP accounts per HutMail user (e.g.: personal Gmail, work Orange)
3. Deduplication by `Message-ID` in the database (not by IMAP flag)
4. Optionally skips messages already read in IMAP (`skip_already_read`)
5. Each new message receives its stable identifier (`01mar.GM.1`, `01mar.GM.2`, etc.)
6. Filtering by configurable rules:
   - Sender whitelist/blacklist
   - Max size per message
   - Priority or blocked keywords

#### Step 2: Aggressive stripping

Each message is cleaned:
- HTML → plain text
- Attachments removed
- Email signatures removed (`-- `, `Sent from my iPhone`, `Envoyé de mon iPad`, etc.)
- Quoted replies removed (`>`, `On ... wrote:`, `Le ... a écrit :`, etc.)
- Noise removed (disclaimers, unsubscribe links, tracking pixels, standalone URLs)
- HTML entities decoded, base64 cleaned
- Whitespace normalized

The stripped body and its size are stored in the database (`stripped_body`, `stripped_size`).

#### Step 3: Bundling with budget management

`pending` messages are aggregated into a bundle, grouped by source account. **The bundle uses a configurable share of the radio budget for full messages, and always appends a screener of remaining messages**:

1. HutMail calculates the remaining budget (`daily_budget_kb` KB/day over 7 rolling days via `budget_entries`)
2. The **message budget** = remaining budget × `bundle_ratio` / 100 (default: 80%)
3. The **screener budget** = remaining budget − message budget
4. `pending` messages are sorted by date (oldest first)
5. Messages are added to the bundle **as whole messages** (never cut mid-message) until the message budget is reached
6. A **screener** of all remaining `pending` messages is appended (identifier, sender, subject, stripped size)
7. If the screener itself exceeds the screener budget, it is truncated with a count: "and X more messages pending"
8. If all pending messages fit within the message budget, no screener is appended

**The budget is a soft limit.** HutMail respects it for automatic bundles, but the skipper can exceed it deliberately via `GET` commands — the boat manages its own airtime.

```
=== HUTMAIL 01mar 09:30 ===

==[ GM — Personal Gmail (beavers@gmail.com) ]==

[01mar.GM.1] From: bob@example.com | Re: Horta | 01mar 08:12
Hey guys!
Confirming Tuesday meetup at Horta harbor, we'll be there around 2pm.
The anchorage is great, turquoise water.

[01mar.GM.2] From: mom@family.fr (+5 +2cc) | Christmas news | 28feb 19:45
Hey sweethearts, how are you doing?
Christmas here was great, we had a big dinner. Grandpa is doing better.
We love you!

==[ OR — Work Orange (beavers@orange.fr) ]==

[28feb.OR.1] From: boss@work.com (→ team@ +3cc) | January statement | 28feb 10:00
Balance as of 01/31: 4521.30 EUR

=== SCREENER (2 messages, 12.4 KB) ===
[28feb.OR.2] newsletter@sailing.fr | "Vendée Globe results" | 8.2 KB
[27feb.OR.3] insurance@maif.fr | "Annual certificate" | 4.2 KB
GET 28feb.OR.2 to download a specific message
=== END ===
```

#### Step 4: Sending and recording

1. The bundle is sent via the **relay SMTP account** to the boat's SailMail address
2. In the database:
   - The `bundle` moves to status `sent`
   - Each included `collected_message` moves from `pending` to `sent`, with `sent_at` and `bundle_id`
   - Messages in the summary remain `pending` (will be in the next bundle)
   - A `budget_entry` is created with the bytes sent
3. **As a courtesy**, sent messages are marked as read in their respective IMAP mailboxes (`\Seen` flag), but the database remains the source of truth

#### Screener

When there are remaining `pending` messages after filling the message budget, the bundle ends with a `=== SCREENER ===` section:
- Lists each remaining message: identifier, sender, subject, stripped size
- The boat can request specific messages: `GET 28feb.OR.2`
- If the screener exceeds the screener budget, it is truncated: "and X more messages pending"
- Messages not included and not requested via `GET` will be **automatically included in the next bundle** (oldest first priority). Nothing is lost — they stay `pending` until sent.

A `GET` response follows the same format: `=== HUTMAIL ===` with the requested messages, then `=== SCREENER ===` with whatever is still pending. The skipper always has an up-to-date view.

### Tracking

HutMail keeps a complete record of all exchanges via the database:

#### Radio budget
- Calculated from `bundles`: `SUM(total_stripped_size) WHERE sent_at >= 7.days.ago`
- Remaining budget = `(daily_budget_kb × 7) - consumed_7d`
- Alerts when budget is tight

#### Sent bundles
- `bundles` table with:
  - Included messages (via `collected_messages.bundle_id`)
  - Summary messages (the `pending` ones not included at send time)
  - Raw vs stripped size
  - Status

#### Individual messages
- `collected_messages` table:
  - Stable identifier (`hutmail_id`)
  - IMAP link (`imap_uid`, `imap_message_id`, `mail_account_id`)
  - Full lifecycle: `pending` → `sent` / `dropped`
  - Traceability: in which bundle, when sent

#### Boat replies
- `boat_replies` table:
  - Link to original message (`in_reply_to_id`)
  - SMTP account used
  - Send status

### Outbound flow (boat → world)

1. HutMail polls the **relay account via IMAP** for boat messages
2. Parsing of the structured format:
   ```
   ===MSG bob@example.com===
   We're arriving Tuesday in Horta
   ===MSG family@beavers.fr===
   All is well, 15 knots of wind
   ```
3. **SMTP account resolution**: for each recipient, HutMail determines which account to send from:
   - Search `collected_messages` for whether this recipient has previously written → use the same `mail_account`
   - Otherwise → use the account marked `is_default`
4. **Send via SMTP** from the appropriate account, with correct headers (`From:`, `Reply-To:`)
5. **Record** in `boat_replies`: link to original message, account used, status
6. Log what was sent

### Email CLI (commands from the boat)

The Beavers can send commands to the server to react:

```
===CMD===
# Message management
DROP LAST             — cancel the last send (too big to download)
DROP 01mar.GM.2 28feb.OR.1   — exclude specific messages from the next send
GET 28feb.OR.2        — request a message from the screener (boat manages its budget)

# Direct sending
SEND bob@example.com "We're arriving Tuesday"
URGENT family@beavers.fr "All is well"  — immediate send

# Aggregation control
PAUSE 3d              — stop aggregation (port of call, wifi available)
RESUME                — resume
STATUS                — receive a summary (pending messages, remaining budget)

# Sender management
WHITELIST add bob@example.com
WHITELIST remove spam@junk.com
BLACKLIST add spam@junk.com
BLACKLIST remove bob@example.com
===END===
```

Comments (`#`) are ignored. Commands are case-insensitive.

**`DROP`** sets the `collected_message` status to `dropped`. It will not be re-proposed. Supports the same implicit wildcards as `GET` (e.g.: `DROP 01mar` drops all pending from March 1st, `DROP GM` drops all pending from mailbox GM).
**`GET`** sends the requested `pending` message(s) in a response that uses the same format as a regular bundle: `=== HUTMAIL ===` with the full messages, followed by `=== SCREENER ===` with any remaining `pending` messages. The budget is not checked — the skipper manages their own airtime.

`GET` supports **implicit wildcards** — each omitted segment broadens the filter to all matching `pending` messages:

```
GET 01mar.GM.1     — one specific message
GET 01mar.GM       — all pending from mailbox GM on 01mar
GET 01mar          — all pending from 01mar, all mailboxes
GET GM             — all pending from mailbox GM, any date
GET 1              — all pending with sequence number 1, all mailboxes and dates
```

Parsing rule: if the argument contains no `.`, it's either a mailbox code (2 uppercase letters) or a sequence number (digits). If it contains `.`, segments are parsed left to right as `DDmon[YY].BB.N`.
**`DROP LAST`** sets all `collected_messages` from the last bundle back to `pending` (they will be re-proposed).

### Web interface

- **Mailbox**: unified view of all accounts, preview of the bundle to be sent, command simulation
- **Accounts**: configuration of IMAP+SMTP mailboxes to monitor (both verified on add)
- **Relay**: relay account and SailMail address configuration
- **Budget**: radio budget visualization over 7 rolling days, KB consumed/remaining
- **History**: sent bundles, included messages, boat replies, statuses
- **Monitoring**: no manual validation, but full visibility into what the system is doing

## Technical decisions

### Database = source of truth

The IMAP status (read/unread) is **never** used to determine whether a message has been collected, sent, or should be ignored. The HutMail database is the sole source of truth:
- **Collection**: deduplication by `Message-ID` in the database, not by IMAP flag
- **Sending**: the `status` field of `collected_messages` determines the lifecycle
- **IMAP marking**: done as a courtesy after sending, so regular mail clients show a clean mailbox

The IMAP `\Seen` flag is used only as an **optional input signal** during collection (`skip_already_read`): if the user has already read a message via wifi/internet, HutMail can skip it.

Reasons:
- The user can read an email on their phone → the `\Seen` flag changes without HutMail having sent it
- An IMAP client can crash → inconsistent flags
- Some IMAP servers don't reliably preserve flags
- The database is local, fast, and fully under HutMail's control

### Integrated screener (not a separate round-trip)

The screener is **not** a separate step requiring a radio round-trip (screener → response → delivery). Instead, it is **always appended** at the end of a bundle when there are remaining `pending` messages. This avoids wasting budget on an extra exchange while still giving the skipper full visibility.

The `bundle_ratio` setting (default: 80%) controls how much of the budget goes to full messages vs. the screener. The skipper can tune this:
- **Higher ratio (90%)**: more messages delivered, smaller screener
- **Lower ratio (70%)**: fewer messages, but a guaranteed comprehensive screener

Every response to the boat uses the same format — whether it's an automatic bundle or a `GET` response: `=== HUTMAIL ===` section with full messages, then `=== SCREENER ===` with remaining messages. The skipper always knows what's pending.

### Radio budget (7 rolling days, soft limit)

- Email budget configurable via `daily_budget_kb` (default: **100 KB/day**, out of ~200 KB/day total bandwidth)
- Tracked over **7 rolling days** via `budget_entries` in the database
- **Soft limit**: HutMail respects the budget for automatic bundles (using `bundle_ratio` to split between messages and screener), but the skipper can exceed it via `GET` — the boat manages its own airtime
- The bundle is cut on **whole message boundaries** (never mid-message)
- `bundle_ratio` (default: **80%**) determines the split: 80% of remaining budget for full messages, 20% for screener

### Stable identifiers

Messages are identified by `DDmon.BB.N` (e.g.: `01mar.GM.1`, `28feb.OR.2`). Benefits:
- Human-readable in Airmail — the mailbox code tells you which account it came from
- Stable: doesn't change when new messages arrive (stored in database)
- Compact: just a few characters
- Zero-padded day for consistent sorting (`01mar`, `09feb`)
- Implicit year unless different (`15jan26.GM.3`)
- Easy to type on an Airmail keyboard

### Stripping pipeline

Two gems handle the heavy lifting, with a custom layer to compensate their gaps:

1. **`html2text`** (soundasleep) — HTML → plain text conversion
   - Handles `<p>`, `<br>`, `<li>`, `<table>`, `<a>` → structured text
   - We post-process: strip URLs from links (useless on radio, waste bytes), clean excess whitespace

2. **`email_reply_parser`** (GitHub) — removes quoted replies and standard signatures
   - Detects `>` quoted blocks, `On ... wrote:` headers, `--` signatures
   - **Gap: English only.** We add French patterns: `Le ... a écrit :`, `De :`, `Envoyé :`

3. **Custom `MessageStripper`** (~50-80 lines) — compensates both gems:
   - Mobile signatures: `Sent from my iPhone`, `Envoyé de mon iPad`, `Get Outlook for iOS`
   - Legal disclaimers: blocks with `DISCLAIMER`, `CONFIDENTIAL`, `AVERTISSEMENT`
   - Unsubscribe noise: `unsubscribe`, `se désinscrire`, `manage preferences`
   - Orphan URLs: lines containing only a URL
   - Whitespace normalization: multiple blank lines → one, trim

**Pipeline:**
```
Email (Mail gem)
  → text/plain if exists, else text/html → html2text, else empty
  → email_reply_parser (quoted replies + signatures)
  → custom MessageStripper (French patterns, mobile sigs, disclaimers)
  → normalize whitespace
  = stripped_body
```

**Attachments:** stripped from body, metadata stored as JSON on `collected_messages`:
```json
[{"name": "facture.pdf", "size": 245000, "content_type": "application/pdf"}]
```
Displayed in bundle: `📎 facture.pdf (245 KB)`. No attachment download via radio (V1).

### Encryption

All personal data is encrypted at rest using Active Record Encryption:
- Passwords: IMAP/SMTP credentials on `users` and `mail_accounts`
- Message content: `from_address`, `to_address`, `subject`, `stripped_body` on `collected_messages`
- Boat replies: `to_address`, `body` on `boat_replies`

### Compression

- **V1: plain text** — no application-level compression. PACTOR already compresses on the radio link (~50-60%). The gain from pre-compression (zlib ~35%) doesn't justify the complexity on the boat side.
- **V2 (if needed)**: zlib on Rails + standalone HTML page with pako.js to decompress on the boat, or a small Windows companion that monitors the Airmail folder.

### Message format

- Plain text, simple human-readable delimiters
- Stable identifiers in brackets (`[01mar.GM.1]`)
- Grouped by source mailbox for readability
- Screener of remaining messages at the end of the bundle
- No JSON, no binary — if the script breaks, the message is still readable in Airmail

#### Compact headers

Every byte counts on the radio link. Message headers are compressed:

- **From**: always shown (sender name or address)
- **To**: omitted if the only recipient is the monitored mailbox. Otherwise abbreviated: `(→ alice@)` for a single extra recipient, or `(+3)` for the count of extra To recipients
- **CC**: shown as count only: `+2cc`. Never the full list
- **Combined example**: `From: mom@family.fr (+5 +2cc)` = 5 other To recipients, 2 CC
- **Reply-To**: shown only if different from From

Examples:
```
[01mar.GM.1] From: bob@example.com | Subject | 01mar 08:12
  → simple email, just From

[01mar.GM.2] From: mom@family.fr (+5 +2cc) | Subject | 01mar 09:00
  → 5 other To recipients, 2 CC

[01mar.OR.1] From: boss@work.com (→ team@ +3cc) | Subject | 01mar 10:00
  → sent to team@, plus 3 CC
```

### Multi-account (IMAP + SMTP)

A HutMail user can configure multiple mailboxes (e.g.: personal Gmail + work Orange). Each account has its IMAP (receiving) and SMTP (sending) config. Both are verified on add. All mailboxes are collected and bundled into a single SailMail send, grouped by account in the message. Boat replies are sent from the correct SMTP account.

### Stack

- **Ruby on Rails 8.1** — vanilla, no CSS framework
  - **Hotwire** (Turbo + Stimulus) for interactivity
  - **Importmaps** for JS (no bundler)
  - **Vanilla CSS** — no Tailwind, no Bootstrap. Hand-written, minimal
  - Pages must be lightweight: minimal DOM, no bloat, fast on slow connections
- **SQLite** for storage
- **ActiveJob** + cron for periodic aggregation
- **Active Record Encryption** for IMAP and SMTP passwords

### Boat side

- **V1**: nothing to install. Plain text readable directly in Airmail.
- **V2**: Windows companion (.exe) or standalone HTML page for automatic compression/decompression.

## Name

**HutMail** — the beaver lodge. Where mail arrives, is filtered, and stored safely. Protected entrance (underwater), dry interior. A nod to Hotmail.

## Market status

No existing solution identified for the "automated shore-side postman" role. Sailors have been doing this manually for 20 years. **pyAirmail** (GitHub: SailingTools) is a boat-side Airmail replacement in Python, but doesn't cover shore-side relaying.

Open source potential: thousands of boats circumnavigating each year have this problem.

---

## Raw notes (to sort)

- When a message is sent to the boat, mark it as read in the respective IMAP mailboxes.
- When the boat sends a reply, send it via SMTP (config to be added to accounts).
- Keep track of what was sent: which email was sent in which bundle. Same for replies.
- Reply from the correct mailbox, and keep track.
- When adding an account, verify both receiving (IMAP) AND sending (SMTP) configs and credentials.
- Radio budget: ~100 KB/day for email. Based on 90 min / 7 rolling days, throughput 0.1–0.6 KB/s. The 200 KB/day is shared with weather/GRIB, so ~100 KB for mail.
- If the bundle exceeds the budget, cut on whole message boundary. Never cut mid-message.
- When cutting, send a summary of remaining messages. The boat can request a specific message with GET. The boat manages if it exceeds its quota.
- Numbering: include the date + mailbox code for a stable ID. Format `DDmon.BB.N` (e.g.: `01mar.GM.1`). Zero-padded day. Year omitted if current year, otherwise `15jan26.GM.3`. BB = 2-letter mailbox code defined by user.
- Messages not included in the current bundle (and not requested via GET) are automatically carried over to the next bundle. Nothing is lost.
- Don't rely on IMAP read/unread status. The HutMail DB is the source of truth. Deduplication by Message-ID. IMAP marking as courtesy only.
- No 35 KB per-message SailMail limit (unconfirmed). The only constraint is the time/bandwidth budget.
- Already-read emails: `skip_already_read` option per account. Default true (if read at marina, not resent via radio). Configurable to false if the crew wants everything.
- Configure the boat's SailMail address + the HutMail relay account (IMAP+SMTP) for communication with the boat. The relay is separate from monitored mail accounts.

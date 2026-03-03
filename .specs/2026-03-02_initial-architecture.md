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

Each collected message receives a **stable identifier** based on its reception date, human-readable and usable in commands:

```
1mar.1    — 1st message of March 1st (current year by default)
1mar.2    — 2nd message of March 1st
28feb.1   — message from February 28th
15jan26.3 — 3rd message from January 15th, 2026 (explicit year if different)
```

Rules:
- Format: `DDmon.N` (day + first 3 letters of month in English + `.` + daily sequence number)
- Year is omitted by default (current year). If the year differs, it's appended: `15jan26.3`
- The identifier is assigned at collection and remains stable (never changes, even if new messages arrive)
- Allows the boat to reference a specific message in commands: `DROP 1mar.2` or `GET 28feb.1`

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

#### `mail_accounts`
| Field | Type | Description |
|-------|------|-------------|
| id | integer | PK |
| user_id | integer | FK → users |
| name | string | Display name ("Personal Gmail") |
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
| hutmail_id | string | Stable identifier (`1mar.1`), unique |
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

#### `budget_entries`
| Field | Type | Description |
|-------|------|-------------|
| id | integer | PK |
| user_id | integer | FK → users |
| date | date | Day |
| bytes_sent | integer | Bytes sent that day |
| bundle_id | integer | FK → bundles (nullable, for traceability) |

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
        - Assign a hutmail_id (1mar.1, 1mar.2, etc.)
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
5. Each new message receives its stable identifier (`1mar.1`, `1mar.2`, etc.)
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

`pending` messages are aggregated into a bundle, grouped by source account. **The bundle respects the radio budget**:

1. HutMail calculates the remaining budget (100 KB/day over 7 rolling days via `budget_entries`)
2. `pending` messages are sorted by date (oldest first)
3. Messages are added to the bundle **as whole messages** (never cut mid-message)
4. If the budget is sufficient: all `pending` messages are included
5. If the budget is exceeded: the bundle is cut, and a **summary of remaining messages** is appended at the end

```
=== HUTMAIL 1mar 09:30 ===

==[ Personal Gmail (beavers@gmail.com) ]==

[1mar.1] From: bob@example.com | Re: Horta | 1mar 08:12
Hey guys!
Confirming Tuesday meetup at Horta harbor, we'll be there around 2pm.
The anchorage is great, turquoise water.

[1mar.2] From: mom@family.fr | Christmas news | 28feb 19:45
Hey sweethearts, how are you doing?
Christmas here was great, we had a big dinner. Grandpa is doing better.
We love you!

==[ Work Orange (beavers@orange.fr) ]==

[28feb.1] From: bank@credit.fr | January statement | 28feb 10:00
Balance as of 01/31: 4521.30 EUR

=== REMAINING (2 messages, 12.4 KB) ===
[28feb.2] newsletter@sailing.fr | "Vendée Globe results" | 8.2 KB
[27feb.1] insurance@maif.fr | "Annual certificate" | 4.2 KB
Reply: GET 28feb.2 to request a specific message
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

#### Remaining messages summary

When the budget doesn't allow sending all messages, the bundle ends with a compact summary of queued messages:
- Identifier, sender, subject, stripped size
- The boat can request a specific message: `GET 28feb.2`
- Messages not included and not requested via `GET` will be **automatically included in the next bundle** (oldest first priority). Nothing is lost — they stay `pending` until sent.

### Tracking

HutMail keeps a complete record of all exchanges via the database:

#### Radio budget
- `budget_entries`: KB sent per day
- Rolling calculation: `SUM(bytes_sent) WHERE date >= 7.days.ago`
- Remaining budget = `(100 KB × 7) - consumed_7d`
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
DROP 1mar.2 28feb.1   — exclude specific messages from the next send
GET 28feb.2           — request a message from the summary (boat manages its budget)

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

**`DROP`** sets the `collected_message` status to `dropped`. It will not be re-proposed.
**`GET`** forces sending a `pending` message in an immediate mini-bundle, without checking the budget.
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

### No systematic screener

The screener (summary sent before messages) was abandoned as a systematic step. Reasons:
- Adds a radio round-trip (screener → response → delivery), costing time and budget
- Aggressive stripping reduces size sufficiently (99% reduction typical)
- The boat can react after the fact with `DROP LAST` if a send is too large
- Simpler = more reliable on a temperamental radio link

However, a **remaining messages summary** is appended at the end of the bundle when the budget doesn't allow sending everything. This summary plays the role of a partial screener.

### Radio budget (7 rolling days)

- Email budget estimated at **100 KB/day** (out of ~200 KB/day total bandwidth)
- Tracked over **7 rolling days** via `budget_entries` in the database
- The budget is not a hard quota on HutMail's side — it's a conservative estimate. If the boat requests a message via `GET`, HutMail sends it even if the budget is exceeded (the boat manages)
- The bundle is cut on **whole message boundaries** (never mid-message)

### Stable identifiers

Messages are identified by `DDmon.N` (e.g.: `1mar.1`, `28feb.2`). Benefits:
- Human-readable in Airmail
- Stable: doesn't change when new messages arrive (stored in database)
- Compact: just a few characters
- Implicit year unless different (`15jan26.3`)
- Easy to type on an Airmail keyboard

### Compression

- **V1: plain text** — no application-level compression. PACTOR already compresses on the radio link (~50-60%). The gain from pre-compression (zlib ~35%) doesn't justify the complexity on the boat side.
- **V2 (if needed)**: zlib on Rails + standalone HTML page with pako.js to decompress on the boat, or a small Windows companion that monitors the Airmail folder.

### Message format

- Plain text, simple human-readable delimiters
- Stable identifiers in brackets (`[1mar.1]`)
- Grouped by source account for readability
- Remaining messages summary at the end of the bundle
- No JSON, no binary — if the script breaks, the message is still readable in Airmail

### Multi-account (IMAP + SMTP)

A HutMail user can configure multiple mailboxes (e.g.: personal Gmail + work Orange). Each account has its IMAP (receiving) and SMTP (sending) config. Both are verified on add. All mailboxes are collected and bundled into a single SailMail send, grouped by account in the message. Boat replies are sent from the correct SMTP account.

### Stack

- **Ruby on Rails 8.1** (Tailwind, Importmaps, Turbo, Stimulus)
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
- Numbering: include the date for a stable ID. Format `DDmon.N` (e.g.: `1mar.1`). Year omitted if current year, otherwise `15jan26.3`.
- Messages not included in the current bundle (and not requested via GET) are automatically carried over to the next bundle. Nothing is lost.
- Don't rely on IMAP read/unread status. The HutMail DB is the source of truth. Deduplication by Message-ID. IMAP marking as courtesy only.
- No 35 KB per-message SailMail limit (unconfirmed). The only constraint is the time/bandwidth budget.
- Already-read emails: `skip_already_read` option per account. Default true (if read at marina, not resent via radio). Configurable to false if the crew wants everything.
- Configure the boat's SailMail address + the HutMail relay account (IMAP+SMTP) for communication with the boat. The relay is separate from monitored mail accounts.

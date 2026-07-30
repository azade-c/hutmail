# Hutmail 🦫

Automated shore-side mail relay for sailors communicating via SSB radio (SailMail/Winlink).

## Stack

Ruby 4.0, Rails 8.1, SQLite 3, Hotwire (Turbo + Stimulus), vanilla CSS/JS, Importmap, Propshaft, Solid Trifecta (Queue/Cable/Cache), Kamal.

## Commands

```bash
bin/setup              # Initial setup
bin/dev                # Dev server
bin/rails test         # Unit tests
bin/rails test:system  # System tests
bin/ci                 # Full CI suite, the gate before handoff
```

## Frontend

- Theme: wood (warm brown) + river (deep blue). CSS vars live in `_global.css`.
- Typography: system font stack. Sailors pull these pages over radio bandwidth, so every kilobyte counts and no page carries weight it does not need.

## Specs

- Architecture: `.specs/2026-03-02_initial-architecture.md` (source of truth)
- Original spec: `.specs/SPEC.md`

## Browser

Use `agent-browser` (skill installed). Vault entries (run `agent-browser auth list`):

- `hutmail-boris` - `boris@castors.ovh` on https://hutmail.azade.dev
- `netcourrier-sailmail` - `sailmailalibi@netcourrier.com`
- `francemel-alibi` - `alibi@francemel.fr` (same Mailo backend as netcourrier - use distinct `--session` for parallel)
- `hey-azade` - `azade@hey.com`

Gmail (`azade.craba@gmail.com`): blocked by Google anti-bot. Use real Chrome with the "Azade" profile clone:
```bash
agent-browser --executable-path "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --profile "Profile 2" open https://mail.google.com
```

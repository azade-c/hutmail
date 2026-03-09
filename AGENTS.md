READ ../garde-rails/RAILS.md BEFORE ANYTHING.
If missing: git clone https://github.com/fcatuhe/garde-rails.git ../garde-rails

# HutMail 🦫

Automated shore-side mail relay for sailors communicating via SSB radio (SailMail/Winlink).

## Stack

Ruby 4.0, Rails 8.1, SQLite 3, Hotwire (Turbo + Stimulus), vanilla CSS/JS, Importmap, Propshaft, Solid Trifecta (Queue/Cable/Cache), Kamal.

## Commands

```bash
bin/setup              # Initial setup
bin/dev                # Dev server
bin/rails test         # Unit tests
bin/rails test:system  # System tests
bin/ci                 # Full CI suite
```

## Generators

Prefer Rails generators:

```bash
bin/rails g model MailAccount name:string imap_server:string
bin/rails g controller MailAccounts index show new create
bin/rails g migration AddShortCodeToMailAccounts short_code:string
```

## Code

- No comments. If needed, use Rails notes (`bin/rails notes`):
  - `TODO:` / `FIXME:` / `OPTIMIZE:`
  - Format: `# TODO: AC 07mar26 description`
- Files < 500 LOC; split if needed.
- Bugs: add regression test.

## Critical Thinking

- Fix root cause (not band-aid).
- Unsure: read more code; if still stuck, ask w/ short options.
- Conflicts: call out; pick safer path.
- Unrecognized changes: assume other agent; keep going; focus your changes. If it causes issues, stop + ask user.
- Leave breadcrumb notes in thread.

## Git

- Commits: Conventional Commits (`feat|fix|refactor|build|ci|chore|docs|style|perf|test`).
- Safe by default: no destructive ops (`reset --hard`, `clean`, `rm`) without consent.
- Keep edits small/reviewable.
- Never commit/push without explicit user request; permission applies to next command only.
- **Never push directly to main.** Always create a branch and open a PR. François merges.

## GitHub CLI

- PRs: use `gh pr view/diff` (no URLs).
- CI: `gh run list/view`, rerun/fix til green.
- PR comments: `gh pr view` + `gh api .../comments --paginate`.
- Given issue/PR URL: use `gh`, not web search.

## CI

- Before handoff: run full gate (`bin/ci`).
- CI red: fix, push, repeat til green.

## Dependencies

New deps: quick health check (recent commits, adoption, maintenance).

## Frontend

Avoid "AI slop" UI. Be opinionated + distinctive.

- No inline `style` attributes in HTML; use utility classes instead.
- Typography: system font stack (no external font requests — lightweight pages).
- Theme: wood (warm brown) + river (deep blue). Use CSS vars from `_global.css`.
- Motion: 1-2 high-impact moments, not random micro-anim.
- **Pages must be lightweight**: minimal DOM, no bloat. Every KB matters — this app serves sailors on radio bandwidth.

## Specs

- Architecture: `.specs/2026-03-02_initial-architecture.md` (source of truth)
- Original spec: `.specs/SPEC.md`

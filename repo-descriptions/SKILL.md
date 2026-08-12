---
name: repo-descriptions
description: >-
  Propose and apply GitHub repo "About" descriptions in BULK, driven by each
  repo's documentation. Produces a review table (repo | current | suggested |
  reason) you approve before anything is written, then applies the approved rows
  with `gh repo edit`. Use whenever the user wants to write, fix, standardize, or
  fill in the short descriptions across many repositories — "my repos have no
  descriptions", "clean up my profile", "suggest better descriptions for all my
  projects", "bulk update repo about text". Reads existing READMEs/markdown; when
  a repo has none worth reading, hand off to the repo-docs skill to generate docs
  first. This is the light, run-often half of the repo cleanup pair.
compatibility: Requires the gh CLI (authenticated, with repo admin scope to edit descriptions) and jq.
---

# repo-descriptions

Give every repo a short, accurate "About" description — the one-liner shown on
the profile and in search. The value is in the **bulk review flow**: you see all
of them in one table, edit in one place, and apply in one shot. Nothing reaches
GitHub until you approve it.

## Two phases, always in this order

This is the heart of the skill. Never collapse them — the gap between them is
where the human review happens.

### Phase 1 — Plan (default; writes nothing to GitHub)

1. **Select** repos with `scripts/select_repos.sh` (shared with repo-docs; wraps
   `gh repo list` with the activity/forks/archived/visibility/list filters). Run
   it with `--help` for flags.
2. For each repo, **read its documentation** — the README first, then any
   `docs/`, then package manifests and the primary language — enough to say what
   the repo *is* and what it's *for*.
3. **Draft a description** (see rules below).
4. **Emit a review file** in two forms:
   - `descriptions-review.json` — the machine source of truth (array of rows).
   - A Markdown table printed to the user for eyeballing.

   Row shape:
   ```json
   { "repo": "owner/name", "current": "old text or empty",
     "suggested": "new one-liner", "reason": "why", "action": "apply" }
   ```
   Set `action` to `"apply"` for real suggestions; `"skip"` when the current one
   is already good (still list it, so the table is complete).

5. **Hand the file to the human.** Tell them: edit `suggested` where you'd word
   it differently, flip `action` to `skip` for any you don't want, then say go.

### Phase 2 — Apply (only after approval)

Run the bundled applier on the (possibly edited) file:

```bash
scripts/apply_descriptions.sh descriptions-review.json --dry-run   # preview first
scripts/apply_descriptions.sh descriptions-review.json             # do it
```

It pushes only rows with `action: "apply"` and a non-empty, changed `suggested`,
via `gh repo edit <repo> --description "…"`, and reports applied/skipped/failed.

## Default scope: all repos, missing-first

By default, suggest for **every** selected repo but sort so repos with **no
description surface at the top** — the gaps are the highest-value edits and you
want them first in the table. `select_repos.sh --sort-missing-first` does this.

Narrow with `--filter` when the user wants a specific pass:

- `--filter missing` — only repos lacking a description (fill gaps, leave the
  rest alone).
- `--filter existing` — only repos that already have one (a polish/rewrite pass).
- `--filter all` — everything (the default).

## What makes a good description

A GitHub description is one line, ~120 chars or less, no trailing period needed,
read at a glance next to dozens of others. Aim for:

- **What it is + what it's for**, concretely. "Bash scripts for provisioning and
  tearing down homelab k3s clusters" beats "My scripts" or "A collection of
  utilities".
- **Lead with the noun**, not the owner or "A/This". Skip "A repo that…".
- **Real specifics from the docs** — the actual domain, stack, or purpose. If
  the README says it's a Terraform module for AWS VPCs, say that.
- **No hype, no filler** ("powerful", "simple", "awesome") unless it's truly
  load-bearing. No emoji unless the repo's own branding uses them.
- **Honesty over polish.** If you can't tell what a repo does from its docs,
  don't invent a confident description — that's the signal to generate docs
  first (below), or mark the row `skip` with a reason.

Preserve a current description's intent when it's already decent — a rewrite
should be clearly better, not just different, or reviewers lose trust in the
table.

## When a repo has no usable docs

A description is only as good as what it's drawn from. If a repo has no README or
nothing worth summarizing, don't guess from the repo name alone. Instead:

- Prefer to **hand off to the `repo-docs` skill** to generate documentation
  first, then read that. Say so in the reason column.
- Or, if docs generation isn't wanted right now, read the code directly enough to
  write an honest one-liner, and note lower confidence in `reason`.
- Or mark the row `skip` with `reason: "no docs — run repo-docs first"` so it's
  visible but not applied.

## Scheduled / recurring runs

For a recurring "keep active repos described" pass, select with
`--pushed-since <days>` so only recently-active repos are considered, generate
the review file, and — if the user has opted into unattended apply — run the
applier directly. Keep the human review for interactive runs; only auto-apply
when explicitly asked, because a description is public-facing profile text.

## Report

Always show the plan as a table before applying, e.g.:

```
| repo           | current                 | suggested                                             | action |
|----------------|-------------------------|-------------------------------------------------------|--------|
| user/homelab   | (none)                  | Bash + k3s homelab: provision, tear down, and back up | apply  |
| user/dotfiles  | my dotfiles             | Zsh, tmux, and Neovim config managed with GNU stow    | apply  |
| user/blog       | Personal blog (Hugo)    | Personal blog (Hugo)                                  | skip   |
```

After applying, show the applier's applied/skipped/failed summary so the user
knows exactly what changed on their profile.

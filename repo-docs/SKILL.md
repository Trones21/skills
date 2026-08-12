---
name: repo-docs
description: >-
  Generate thorough documentation (README and/or a docs/ set) for GitHub repos
  by reading their actual source code, then commit and push it. Built for BULK
  passes across a whole profile or org, but works on a single repo too. Use this
  whenever the user wants to document, add READMEs to, or improve/refresh the
  docs across many repositories at once — phrases like "document all my repos",
  "generate READMEs for my projects", "my repos have no docs", "bulk docs
  cleanup". Also use it as the upstream step for repo-descriptions when a repo
  has no usable markdown to summarize. This is the heavy, run-rarely half of the
  repo cleanup pair.
compatibility: Requires the gh CLI (authenticated) and jq. Git must be able to push to the target repos.
---

# repo-docs

Generate real documentation from a repo's code and land it in the repo. The goal
is docs that a stranger (or future-you) could actually use — not a templated
stub. Because this runs across many repos, the work must be **safe, resumable,
and honest about what it changed**.

## When to reach for this

- "Document all my repos" / "half my projects have no README" — the bulk case.
- Refreshing stale docs after a repo changed a lot.
- As the first stage before `repo-descriptions`: a good description comes from a
  good README, so generate docs first when a repo has none worth reading.

## The shape of a run

1. **Select** the repos to work on.
2. **For each repo**: shallow-clone it, read enough code to understand it, write
   docs at the requested depth, then commit and push.
3. **Report** a summary table: repo, what was generated, commit URL (or "skipped
   — already well documented").

Work one repo to completion before starting the next. If a repo fails (clone
error, protected branch, nothing worth documenting), record it and move on —
one bad repo must never sink the batch.

## Selecting repos

Use the bundled `scripts/select_repos.sh` — it wraps `gh repo list` with the
filters this pair shares (activity window, forks, archived, visibility, explicit
list). It emits one JSON object per line.

```bash
# Active repos only, skip forks/archived (both are excluded by default):
scripts/select_repos.sh --pushed-since 180

# A specific set:
scripts/select_repos.sh --repos cli,api,dotfiles
```

Run `scripts/select_repos.sh --help` for every flag. Default excludes forks and
archived repos, because you rarely want to write docs into someone else's fork
or a repo you've frozen.

Before doing real work across many repos, **show the selected list and get a
go-ahead** unless the user already said "just do it" or this is a scheduled/
non-interactive run. Writing commits into dozens of repos is not something to
start on an ambiguous request.

## Depth: what to actually produce

Pick with `--depth` (default `standard`). Depth controls scope, never quality —
even `readme` should be genuinely useful.

- **`readme`** — One strong `README.md`: what it is, why it exists, install,
  usage with real examples pulled from the code, and how to run it. Best for
  small tools and scripts.
- **`standard`** (default) — The README above, plus a short `docs/overview.md`
  that maps the codebase (key modules/dirs and what each does). Best for most
  projects.
- **`deep`** — `standard` plus a `docs/` set as the code warrants:
  `architecture.md` (how the pieces fit, data flow), `usage.md` (task-oriented
  guides), and a reference doc (commands / API surface / config). Only add files
  the repo actually justifies — don't pad a 200-line tool into six documents.

## Writing docs that are true

The single most important rule: **document what the code does, not what you wish
it did.** Read before you write.

- Ground every claim in the source. Install steps come from the actual manifest
  (`package.json`, `pyproject.toml`, `go.mod`, `Makefile`, Dockerfile…). Usage
  examples come from real entry points, CLI definitions, and tests — tests are
  the best source of "how is this actually called".
- If the language/build tooling is ambiguous, inspect the repo, don't assume.
- Never invent flags, env vars, endpoints, or license terms. If you can't
  confirm something, leave it out or mark it clearly as a TODO for the human.
- Match the repo's existing voice and formatting if it has docs already.

## Don't clobber good work

Existing docs are a signal someone cared. Before overwriting:

- If a `README.md` (or target file) already exists and is substantive, **refresh
  rather than replace** — preserve badges, custom sections, screenshots, and the
  author's framing; update what's stale; fill what's missing. Prefer additive
  edits.
- If the existing docs are already solid and current, **skip the repo** and say
  so in the report. A no-op is a valid, good outcome — churn for its own sake
  just creates noisy diffs.
- Never delete non-doc files. This skill only writes Markdown docs.

## Landing the changes

Default is **direct commit to the repo's default branch and push** — the fast
path the user asked for.

- Work in a fresh clone under a scratch dir (e.g. `$TMPDIR/repo-docs/<name>`),
  not the user's working copies.
- Detect the default branch (`gh repo view --json defaultBranchRef`) — don't
  assume `main`.
- One focused commit per repo. Suggested message:
  `docs: generate documentation from source` (or `docs: refresh …` on updates).
  Keep the body to a short list of files added/updated.
- Push with `git push`. If the default branch is protected and a direct push is
  rejected, **fall back to a branch + PR for that repo** and note it in the
  report rather than failing.

Optional `--mode=pr` opens a `chore/docs` branch and a PR for every repo instead
of committing directly — use it when the user wants a review gate.

Never force-push. Never touch history beyond the single new commit.

## Non-interactive / scheduled runs

For cron-style "keep active repos documented" runs, support `--yes` to skip the
confirmation prompt and pair it with `--pushed-since` so only recently-active
repos are touched. The skill itself isn't the scheduler — a cron/scheduled task
invokes it — but it must be safe to run unattended: clone to scratch, one commit
per repo, skip repos that are already fine, and emit a machine-readable summary.

## Final report

End with a table so a bulk run is scannable:

```
| repo            | depth    | action   | files                         | commit / PR                 |
|-----------------|----------|----------|-------------------------------|-----------------------------|
| user/cli        | standard | created  | README.md, docs/overview.md   | <commit url>                |
| user/api        | deep     | refreshed| README.md, docs/architecture… | <commit url>                |
| user/old-thing  | —        | skipped  | already well documented       | —                           |
| user/protected  | standard | pr       | README.md                     | <pr url> (branch protected) |
```

Then hand off: if the user's next goal is descriptions, the freshly written
READMEs are exactly what `repo-descriptions` reads.

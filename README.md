# skills

Generic, repo-agnostic [Claude Code skills](https://code.claude.com/docs) —
reusable across any project, not tied to a single repo. (Repo-specific skills
live in their own repos alongside the code they serve.)

## Available skills

### Repo cleanup pair

Two skills for doing a bulk "accuracy pass" over all the repos on a profile or
org. They chain: generate docs, then describe from those docs.

| Skill | What it does | Cadence |
|-------|--------------|---------|
| [`repo-docs`](./repo-docs) | Reads a repo's source and generates real documentation (README and/or a `docs/` set at `--depth readme\|standard\|deep`), then commits + pushes. Bulk or single repo. | Heavy — run rarely |
| [`repo-descriptions`](./repo-descriptions) | Proposes GitHub "About" descriptions from each repo's docs, shows a **review table** (repo \| current \| suggested \| reason), and applies the approved rows with `gh repo edit`. Defaults to all repos, missing-first. | Light — run often |

**Shared design:**
- `scripts/select_repos.sh` (in both) wraps `gh repo list` with the common
  filters: `--pushed-since`, `--filter all|missing|existing`, `--visibility`,
  `--include-forks`, `--include-archived`, `--repos`, `--sort-missing-first`.
  Forks and archived repos are excluded by default.
- **Plan before write.** `repo-descriptions` always emits a review file you edit
  before anything reaches GitHub; `apply_descriptions.sh` pushes only approved,
  changed rows.
- **Scheduling-friendly.** Pair `--pushed-since <days>` with non-interactive
  apply to run either skill from a cron/scheduled task over just the active repos.

**Requirements:** the [`gh` CLI](https://cli.github.com/) (authenticated) and
`jq`. Editing descriptions needs repo admin scope.

### Personal data

| Skill | What it does | Cadence |
|-------|--------------|---------|
| [`inbox-to-dataset`](./inbox-to-dataset) | Turns a labelled email archive into a structured, publishable dataset — scout, fix a schema, paginate the pull durably, group events into entities, anonymise, state the sampling bias. | Heavy once, then incremental |

The extraction is the expensive part and the skill is mostly about not paying
for it twice: mail connectors are remote, so every message passes through the
model to be read. A few thousand messages is a long grind; a later refresh is
one pass.

Bundled scripts are generic — `merge_pages.py` dedupes the per-page extraction
files and reports coverage, `check_leaks.py` cross-references real names against
every published free-text field and exits non-zero if any survived
pseudonymisation.

Worked example: six years of job-search mail →
[live dashboard](https://thomasrones.com/job-search) ·
[write-up](https://thomasrones.com/projects/job-search-measured).

## Layout

Each skill is a self-contained directory with a `SKILL.md` and any bundled
`scripts/`, so it can be copied or symlinked into `~/.claude/skills/` on its own.

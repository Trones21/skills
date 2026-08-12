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

## Layout

Each skill is a self-contained directory with a `SKILL.md` and any bundled
`scripts/`, so it can be copied or symlinked into `~/.claude/skills/` on its own.

---
name: mirror-remotes
description: >-
  Set up, backfill, and audit an automatic secondary ("backup") git remote on
  GitLab.com for every repo, pushed by a global pre-push hook whenever you push
  to origin. Use when the user wants a live off-GitHub copy of their code, asks
  why a repo has no backup remote, wants to know which repos are unmirrored or
  stale, wants to backfill mirrors across all their repos at once, or is
  troubleshooting a mirror that silently stopped working. Complements a periodic
  snapshot backup (tarball → S3) rather than replacing it — this half carries
  full history, every branch and every tag, continuously. The bulk/audit half of
  the backup story; the snapshot tool is the cold half.
compatibility: >-
  Requires git, curl, and jq. Needs a GitLab.com personal access token with the
  `api` scope (project creation only) and, for the default ssh transport, an ssh
  key registered with GitLab.
---

# mirror-remotes

> **Status: not yet run for real.** Nothing here has ever talked to gitlab.com,
> and `install` has never been run on a real machine. Treat the GitLab half as a
> draft until someone completes a first run. Details in
> [What is and isn't verified](#what-is-and-isnt-verified) at the bottom — read
> it before trusting this as a backup.

A second remote is only a backup if something pushes to it. This skill installs
the thing that does the pushing, then keeps you honest about coverage.

## What the machinery actually is

One global hook, not 31 per-repo setups:

```
git config --global core.hooksPath ~/.githooks   # done by `git-backup install`
```

On every `git push`, `~/.githooks/pre-push` runs `git-backup hook-run`, which:

1. exits immediately if the repo opted out (`git config backup.disabled true`),
   if the push *is* the mirror push, or if `origin_filter` excludes this origin;
2. **warns you when there is no `backup` remote**, then creates the GitLab
   project and adds the remote — once, with an hour-long cooldown so a broken
   token warns hourly instead of on every push;
3. fires a **detached** push of all branches and tags to the mirror.

A mirror failure warns and is logged. It never blocks or fails your real push.

## Setup, in order

```bash
scripts/git-backup install     # hook + config template at ~/.config/git-backup/config
# put a GitLab token with the `api` scope where the config can find it
scripts/git-backup doctor      # verifies hook, config, token, and ssh auth
scripts/git-backup sync-all    # backfill: create + push mirrors for existing repos
```

`sync-all` is the only bulk step, and it is idempotent — safe to re-run after
adding repos or fixing a failure.

## Auditing coverage

```bash
scripts/git-backup status ~/gh
```

Columns: repo, whether a mirror remote exists, how many days since the last
successful mirror push, and notes. Three findings matter:

- **`MISSING`** — never pushed since install, or creation failed. Fix with
  `git-backup ensure-remote` in that repo, or re-run `sync-all`.
- **`never`** — remote exists but nothing ever landed. Usually auth; check the
  log at `~/.local/state/git-backup/mirror.log`.
- **`hook SHADOWED`** — the repo sets its own `core.hooksPath` (husky does this).
  `core.hooksPath` is winner-take-all, so the global hook never runs there and
  the repo silently stops mirroring. This is the failure mode that looks fine
  from every other angle, so surface it prominently. Fix by chaining our hook
  from theirs, or by `git-backup sync` on a schedule for that repo.

A growing `age` column across many repos means the hook stopped firing globally
— check `git config --global core.hooksPath` first.

## Judgment calls to raise with the user

These are the parts a script should not decide alone.

- **Secret blast radius.** Mirroring doubles the number of places a leaked
  credential lives. Before a first `sync-all`, ask whether any repo has secrets
  in its *history* — mirroring them to a second provider means a second place to
  rotate and scrub. Repos that fail that test should be `git-backup disable`d
  until the history is cleaned.
- **Client or third-party work.** Default is mirror-everything. Contract work
  may have terms about where the code may be stored. Flag those for opt-out.
- **Clones of other people's repos.** No reason to mirror them. Either
  `disable` per repo or set `origin_filter` in the config to a regex matching
  your own namespace.
- **Big repos.** The first mirror push of a large history is slow. It is
  detached so it won't hold up the terminal, but say so rather than letting the
  user wonder why the log is quiet.

## Non-obvious constraints, learned the hard way

Keep these in mind before "simplifying" the hook — both were verified against
git 2.51 and both bite silently.

- `git push --all --tags` is **rejected** by git ("options '--tags' and
  '--all/--branches' cannot be used together"). Mirroring is necessarily two
  pushes.
- `git rev-parse --git-path hooks/pre-push` **honors `core.hooksPath`**, so
  under a global hooksPath it resolves to the global hook itself. Chaining
  through it recurses forever. The repo-local path must be built from
  `git rev-parse --absolute-git-dir`, with an `-ef` inode guard as backstop.
- The mirror push uses `--no-verify` so it cannot re-enter the hook.
- The mirror push is **not** `--force` and **not** `--mirror` by default. Both
  would let a bad local state destroy history on the backup, which defeats the
  point. `force = true` in the config is available if the user insists.

## Relationship to the snapshot backup

The `github-backup` Lambda stores a tarball of each repo's **default branch**,
monthly. That loses history, other branches, and tags, and can be up to 30 days
stale. This skill covers exactly that gap. Neither replaces the other:

| | snapshot → S3 | mirror remote |
|---|---|---|
| history | no | yes |
| all branches / tags | no | yes |
| freshness | monthly | every push |
| survives GitLab outage | yes | no |
| survives S3/AWS loss | no | yes |

When the user asks "am I backed up?", answer for both halves, and say which
repos are missing from each.

## What is and isn't verified

The split matters, because the tested half is the half that could break your
day, and the untested half is the half that decides whether you actually have a
backup.

**Exercised, against local bare repos (git 2.51):**

- an unreachable mirror warns but does not block or fail the push to origin
- the hook does not invoke itself under a global `core.hooksPath`
- a repo-local `pre-push` is chained, receives the correct argv and ref list on
  stdin, and its rejection vetoes the push
- repeated creation failures rate-limit to one warning per hour
- all branches *and* tags reach the mirror, local-only branches included
- pushing directly to the `backup` remote does not re-trigger mirroring
- `status` reporting, `origin_filter` exclusion, slug and config parsing

**Never run, not once:**

- **every GitLab API call** — `POST /projects`, the `GET /projects/:path`
  existence check, `GET /namespaces` resolution, `GET /user`. The request
  shapes are from the documented v4 API, not from a live response. Assume at
  least one field name or status code is wrong.
- **ssh transport** — the `git@host:ns/path.git` URL form and whether pushes to
  a freshly created project authenticate
- **`install`** on a real machine, including the refuse-to-clobber branch when
  `core.hooksPath` is already set
- **`doctor`** — the token and ssh probes, and how they read on failure
- **`sync-all`** at real scale, over real repo names, against real history sizes

### Completing the first run

Do it on one repo, not thirty-one:

```bash
git-backup install
git-backup doctor                      # expect this to be where problems surface
cd ~/gh/some-small-repo
git-backup ensure-remote --dry-run     # prints the target path, touches nothing
git-backup ensure-remote               # first real API call
git-backup sync
```

Confirm on gitlab.com that the project exists, is **private**, and has every
branch and tag. Then push a commit normally and check that the hook mirrors it
without you asking. Only after that is `sync-all` worth running.

If the first API call fails, `~/.local/state/git-backup/mirror.log` has the
response body — `api_err()` surfaces GitLab's `message` field, which is usually
specific about the offending parameter.

Delete this section once a first run succeeds, and say what git and GitLab
versions it was verified against.

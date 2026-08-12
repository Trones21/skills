#!/usr/bin/env bash
#
# select_repos.sh — Enumerate GitHub repos for a bulk operation, applying the
# common selection filters both skills share. Emits one JSON object per line
# (JSONL) so callers can pipe into `jq`, a while-read loop, or a table builder.
#
# Emitted fields per repo:
#   nameWithOwner, name, owner, description, pushedAt, isFork, isArchived,
#   isPrivate, visibility, primaryLanguage, url
#
# Requires: gh (authenticated), jq.
#
# Usage:
#   select_repos.sh [flags]
#
# Flags:
#   --owner OWNER          Owner to list (default: the authenticated user).
#   --pushed-since DAYS     Keep only repos pushed within the last DAYS days.
#                           This is the "only active repos" lever — also what
#                           makes a scheduled run cheap.
#   --visibility V          public | private | all   (default: all)
#   --include-forks         Include forks (default: excluded).
#   --include-archived      Include archived repos (default: excluded).
#   --filter F              Filter by description presence:
#                             all      — every repo (default)
#                             missing  — only repos with NO description
#                             existing — only repos that already have one
#   --repos a,b,c           Restrict to this explicit comma-separated list of
#                           repo names (matched against `name`, not owner/name).
#   --limit N               Max repos to fetch from the API (default: 1000).
#   --sort-missing-first     Sort output so description-less repos come first,
#                           then by most-recently-pushed. Handy for review tables.
#
# Examples:
#   select_repos.sh --pushed-since 90 --exclude-archived
#   select_repos.sh --filter missing --sort-missing-first
#   select_repos.sh --owner myorg --visibility public --repos api,cli,web

set -euo pipefail

OWNER=""
PUSHED_SINCE=""
VISIBILITY="all"
INCLUDE_FORKS=0
INCLUDE_ARCHIVED=0
FILTER="all"
REPOS=""
LIMIT=1000
SORT_MISSING_FIRST=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --owner) OWNER="$2"; shift 2 ;;
    --pushed-since) PUSHED_SINCE="$2"; shift 2 ;;
    --visibility) VISIBILITY="$2"; shift 2 ;;
    --include-forks) INCLUDE_FORKS=1; shift ;;
    --include-archived) INCLUDE_ARCHIVED=1; shift ;;
    --filter) FILTER="$2"; shift 2 ;;
    --repos) REPOS="$2"; shift 2 ;;
    --limit) LIMIT="$2"; shift 2 ;;
    --sort-missing-first) SORT_MISSING_FIRST=1; shift ;;
    -h|--help) sed -n '2,40p' "$0"; exit 0 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done

# gh repo list uses the authenticated user when no owner is given.
gh_args=(repo list)
[[ -n "$OWNER" ]] && gh_args+=("$OWNER")
gh_args+=(--limit "$LIMIT" --json \
  nameWithOwner,name,owner,description,pushedAt,isFork,isArchived,isPrivate,visibility,primaryLanguage,url)

# Visibility is a first-class gh flag; let the API do that filter.
case "$VISIBILITY" in
  public)  gh_args+=(--visibility public) ;;
  private) gh_args+=(--visibility private) ;;
  all)     : ;;
  *) echo "invalid --visibility: $VISIBILITY (want public|private|all)" >&2; exit 2 ;;
esac

# Build a jq program that applies the remaining filters. gh returns a JSON array;
# we normalize a couple of nested fields, filter, optionally sort, then stream JSONL.
jq_prog='
  map(
    .owner = (.owner.login // .owner) |
    .primaryLanguage = (.primaryLanguage.name // null)
  )
'

if [[ $INCLUDE_FORKS -eq 0 ]]; then
  jq_prog+=' | map(select(.isFork == false))'
fi
if [[ $INCLUDE_ARCHIVED -eq 0 ]]; then
  jq_prog+=' | map(select(.isArchived == false))'
fi

case "$FILTER" in
  all) : ;;
  missing)  jq_prog+=' | map(select((.description // "") == ""))' ;;
  existing) jq_prog+=' | map(select((.description // "") != ""))' ;;
  *) echo "invalid --filter: $FILTER (want all|missing|existing)" >&2; exit 2 ;;
esac

if [[ -n "$PUSHED_SINCE" ]]; then
  cutoff_arg="$PUSHED_SINCE"
  jq_prog+=" | map(select((.pushedAt | fromdateiso8601) >= (now - ($cutoff_arg * 86400))))"
fi

if [[ -n "$REPOS" ]]; then
  # Turn a,b,c into a jq array literal and keep only matching names.
  repos_json=$(printf '%s' "$REPOS" | jq -R 'split(",") | map(gsub("^\\s+|\\s+$";""))')
  jq_prog+=" | map(select(.name as \$n | ($repos_json | index(\$n))))"
fi

if [[ $SORT_MISSING_FIRST -eq 1 ]]; then
  # has-description ascending (false<true so empty sorts first), then newest push.
  jq_prog+=' | sort_by([((.description // "") != ""), ( -(.pushedAt | fromdateiso8601))])'
fi

jq_prog+=' | .[]'

gh "${gh_args[@]}" | jq -c "$jq_prog"

#!/usr/bin/env bash
#
# apply_descriptions.sh — Apply an approved description review file to GitHub.
#
# Reads the JSON review file produced during the plan phase (after the human has
# edited it: tweaked `suggested`, flipped `action`), and pushes each approved
# description with `gh repo edit`. This is the ONLY step that writes to GitHub.
#
# Review file format: a JSON array (or JSONL) of rows shaped like:
#   { "repo": "owner/name", "current": "...", "suggested": "...",
#     "reason": "...", "action": "apply" }   # action: apply | skip
#
# Only rows with action == "apply" and a non-empty, changed `suggested` are
# pushed. Everything else is reported and left untouched.
#
# Requires: gh (authenticated), jq.
#
# Usage:
#   apply_descriptions.sh REVIEW.json [--dry-run]
#
#   --dry-run   Print the gh commands that WOULD run, change nothing.

set -euo pipefail

FILE="${1:-}"
DRY=0
[[ "${2:-}" == "--dry-run" ]] && DRY=1
if [[ -z "$FILE" || ! -f "$FILE" ]]; then
  echo "usage: apply_descriptions.sh REVIEW.json [--dry-run]" >&2
  exit 2
fi

# Accept either a JSON array or JSONL; normalize to a stream of objects.
normalize() {
  if jq -e 'type == "array"' "$FILE" >/dev/null 2>&1; then
    jq -c '.[]' "$FILE"
  else
    jq -c '.' "$FILE"
  fi
}

applied=0 skipped=0 failed=0
while IFS= read -r row; do
  repo=$(jq -r '.repo' <<<"$row")
  action=$(jq -r '.action // "apply"' <<<"$row")
  suggested=$(jq -r '.suggested // ""' <<<"$row")
  current=$(jq -r '.current // ""' <<<"$row")

  if [[ "$action" != "apply" ]]; then
    echo "skip    $repo (action=$action)"; skipped=$((skipped+1)); continue
  fi
  if [[ -z "$suggested" ]]; then
    echo "skip    $repo (empty suggested)"; skipped=$((skipped+1)); continue
  fi
  if [[ "$suggested" == "$current" ]]; then
    echo "skip    $repo (unchanged)"; skipped=$((skipped+1)); continue
  fi

  if [[ $DRY -eq 1 ]]; then
    echo "DRYRUN  gh repo edit $repo --description \"$suggested\""
    applied=$((applied+1)); continue
  fi

  if gh repo edit "$repo" --description "$suggested"; then
    echo "applied $repo"; applied=$((applied+1))
  else
    echo "FAILED  $repo" >&2; failed=$((failed+1))
  fi
done < <(normalize)

echo "---"
echo "applied=$applied skipped=$skipped failed=$failed"
[[ $failed -eq 0 ]]

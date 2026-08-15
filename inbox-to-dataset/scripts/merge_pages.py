#!/usr/bin/env python3
"""Merge per-page JSONL extraction files into one deduped stream.

The extraction phase writes one file per page of search results so an
interrupted pull is resumable. This merges them, drops duplicates by message id,
and reports enough of a summary to notice a page that came back empty or a
message type that only appears in half the corpus.

    python3 merge_pages.py raw/ --out all.jsonl
    python3 merge_pages.py raw/ --id-field m --type-field t --date-field d
"""

import argparse
import glob
import json
import os
import sys
from collections import Counter


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("directory", help="directory holding page-*.jsonl files")
    ap.add_argument("--glob", default="*.jsonl", help="filename pattern (default: *.jsonl)")
    ap.add_argument("--out", help="write merged JSONL here (default: stdout summary only)")
    ap.add_argument("--id-field", default="m", help="unique message id field (default: m)")
    ap.add_argument("--type-field", default="t", help="event type field (default: t)")
    ap.add_argument("--date-field", default="d", help="ISO date field (default: d)")
    args = ap.parse_args()

    paths = sorted(glob.glob(os.path.join(args.directory, args.glob)))
    if not paths:
        print(f"no files matching {args.glob} in {args.directory}", file=sys.stderr)
        return 1

    seen: dict[str, dict] = {}
    dupes = 0
    malformed = 0
    per_file = []

    for path in paths:
        kept_here = 0
        with open(path) as fh:
            for lineno, line in enumerate(fh, 1):
                line = line.strip()
                if not line:
                    continue
                try:
                    rec = json.loads(line)
                except json.JSONDecodeError as e:
                    malformed += 1
                    print(f"  ! {os.path.basename(path)}:{lineno} {e}", file=sys.stderr)
                    continue
                key = rec.get(args.id_field)
                if key is None:
                    malformed += 1
                    print(f"  ! {os.path.basename(path)}:{lineno} missing '{args.id_field}'", file=sys.stderr)
                    continue
                if key in seen:
                    dupes += 1
                    continue
                seen[key] = rec
                kept_here += 1
        per_file.append((os.path.basename(path), kept_here))

    records = list(seen.values())
    dates = sorted(r[args.date_field] for r in records if r.get(args.date_field))

    print(f"files            {len(paths)}")
    print(f"unique records   {len(records)}")
    print(f"duplicates       {dupes}")
    if malformed:
        print(f"MALFORMED        {malformed}")
    if dates:
        print(f"date range       {dates[0]} .. {dates[-1]}")

    empty = [name for name, n in per_file if n == 0]
    if empty:
        print(f"\nEMPTY PAGES ({len(empty)}) — likely a failed pull, check these:")
        for name in empty:
            print(f"  {name}")

    types = Counter(r.get(args.type_field, "(none)") for r in records)
    print("\nby type:")
    for t, n in types.most_common():
        print(f"  {t:16s} {n}")

    if args.out:
        records.sort(key=lambda r: r.get(args.date_field, ""))
        with open(args.out, "w") as fh:
            for r in records:
                fh.write(json.dumps(r, ensure_ascii=False) + "\n")
        print(f"\nwrote {len(records)} records -> {args.out}")

    return 0


if __name__ == "__main__":
    sys.exit(main())

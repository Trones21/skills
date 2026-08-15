#!/usr/bin/env python3
"""Verify that no real entity name survives in a public, pseudonymised dataset.

Pseudonymising the name column is the obvious step and is not sufficient: real
names hide inside free-text fields. "Senior Software Engineer, Upstart Bank"
survives any scheme that only rewrites the company column.

This takes the private build (real names) and the public build (pseudonyms),
and cross-references every real name against every published free-text field.

    python3 check_leaks.py private.json public.json \
        --name-field company --check-fields role

    # records nested under a key
    python3 check_leaks.py private.json public.json --records-key applications \
        --name-field company --check-fields role,notes

Exits non-zero if anything leaked, so it can gate a publish step.
"""

import argparse
import json
import re
import sys


def load_records(path: str, key: str | None):
    with open(path) as fh:
        blob = json.load(fh)
    if key:
        return blob[key]
    if isinstance(blob, list):
        return blob
    for candidate in ("records", "items", "data", "rows"):
        if isinstance(blob.get(candidate), list):
            return blob[candidate]
    raise SystemExit(
        f"{path}: could not find a record list — pass --records-key with the right key"
    )


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("private", help="build containing the real names")
    ap.add_argument("public", help="build intended for publication")
    ap.add_argument("--records-key", help="key holding the record list, if nested")
    ap.add_argument("--name-field", required=True, help="field holding the entity name")
    ap.add_argument("--check-fields", required=True,
                    help="comma-separated public fields to scan for leaks")
    ap.add_argument("--min-length", type=int, default=5,
                    help="ignore names shorter than this; short ones are usually "
                         "ordinary words and produce false positives (default: 5)")
    ap.add_argument("--allow", default="",
                    help="comma-separated names that are fine to publish "
                         "(e.g. vendors that are legitimately named in another column)")
    args = ap.parse_args()

    priv = load_records(args.private, args.records_key)
    pub = load_records(args.public, args.records_key)
    fields = [f.strip() for f in args.check_fields.split(",") if f.strip()]
    allow = {a.strip().lower() for a in args.allow.split(",") if a.strip()}

    names = {
        str(r[args.name_field]).strip()
        for r in priv
        if r.get(args.name_field) and len(str(r[args.name_field]).strip()) >= args.min_length
    }
    names = {n for n in names if n.lower() not in allow}

    print(f"private records  {len(priv)}")
    print(f"public records   {len(pub)}")
    print(f"names checked    {len(names)}")
    print(f"fields scanned   {', '.join(fields)}")

    leaks: dict[str, list] = {}
    for name in names:
        pattern = re.compile(rf"\b{re.escape(name)}\b", re.I)
        for i, rec in enumerate(pub):
            for f in fields:
                val = rec.get(f)
                if isinstance(val, str) and pattern.search(val):
                    leaks.setdefault(name, []).append((i, f, val))

    if not leaks:
        print("\nOK — no real names found in the published free-text fields")
        return 0

    print(f"\nLEAKED ({len(leaks)} names):")
    for name, hits in sorted(leaks.items()):
        print(f"\n  {name}  ({len(hits)} occurrence{'s' if len(hits) != 1 else ''})")
        for i, f, val in hits[:3]:
            print(f"    record {i} .{f} = {val!r}")
        if len(hits) > 3:
            print(f"    … and {len(hits) - 3} more")
    print("\nScrub these from the published fields before publishing.")
    return 1


if __name__ == "__main__":
    sys.exit(main())

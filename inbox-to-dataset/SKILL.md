---
name: inbox-to-dataset
description: >-
  Turn a labelled email archive into a structured dataset you can analyse and
  publish. Use when someone wants to count or chart something that only exists
  in their inbox — "how many jobs have I applied to", "analyse my Gmail",
  "build a dashboard from my email", "what does my inbox say about X",
  "turn my newsletters/receipts/invoices into data". Covers the whole path:
  scouting the messages, fixing a record schema before extraction, paginating
  the pull durably, grouping events into entities, anonymising for publication,
  and stating the sampling bias. The extraction is the expensive step and this
  skill is mostly about not paying for it twice.
compatibility: Requires an email connector (Gmail via claude.ai connectors, or any MCP mail server exposing label/thread search). Python 3 for the bundled scripts.
---

# inbox-to-dataset

Mail archives are the most under-used personal dataset there is. Anyone who has
been labelling mail for a few years is sitting on a longitudinal record of their
own behaviour that no product will hand back to them.

The work is not analysis. The work is **extraction**, and it is expensive in a
way that surprises people, so most of this skill is about spending that cost
once and never again.

## Understand the cost before promising anything

Mail connectors are remote tools. There is no local database to query — every
page of search results comes back through the model, and the model reads each
message to decide what it is. A regex cannot do this: "Thank you for your
interest in Acme", "Important information about your application", and "Follow
up from Initech" are all rejections, and only reading them tells you that.

Concretely, the reference run below was **1,726 messages across 31 paginated
passes**. That's the shape of it: a few hundred messages is quick, a few
thousand is a long grind.

Say this out loud to the user before starting. If they expected five minutes,
they should hear the real number first — and they should hear that a refresh
later is one pass, not thirty-one.

## Phase 1 — Scout before you extract

**Do not start pulling until you have looked at real messages.** Pull a single
page and read it.

You are answering four questions:

1. **Which labels or queries define the corpus?** List them (`list_labels` in
   Gmail) and check the counts. Labels are usually applied at thread level,
   which means a thread can carry several.
2. **What is actually in the messages?** Where does the entity name live — the
   subject, the first line, the sender domain? Is the sender a vendor
   (Greenhouse, Lever, Workday) or the organisation itself?
3. **What event types exist?** This is the taxonomy you will be stuck with.
   Sample widely enough that a fifth type doesn't appear at message 900.
4. **Is the unit the message or the thread?** Threads collapse unrelated
   messages when subjects match — five separate applications to the same company
   can land in one thread with an identical "Thank you for your application"
   subject.

## Phase 2 — Fix the record schema, then never change it

Write down the per-message record before extracting. Every field you leave out
is either a full second pass or a hole in the back half of the data.

A record that has worked:

```json
{"m":"<message id>","d":"2026-08-13T03:15","co":"<entity>","r":"<detail>",
 "t":"<event type>","s":"<sender domain>"}
```

Keep it flat, short-keyed and one line per message — you will be writing
thousands of these and the tokens are real. Keep the message id: it is the
dedupe key and the way back to the source if a record looks wrong.

Add a free-text `note` only for genuine oddities, not for every record.

## Phase 3 — Extract, writing to disk as you go

**One file per page of results.** `raw/page-01.jsonl`, `raw/page-02.jsonl`, …

This is the single most important instruction in the skill. A long extraction
that exists only in the conversation is one interruption, context limit, or
mistake away from being repeated from scratch. Files on disk are the thing that
makes the pull resumable.

The loop:

1. Search with a page token, largest page size the connector allows.
2. Read the results and emit one record per relevant message.
3. Write that page's file.
4. Repeat with the next page token until there isn't one.

Skip the user's own sent messages. Record ambiguous ones with a type of `other`
rather than dropping them, so counts stay auditable.

Merge and check coverage with the bundled script:

```bash
python3 scripts/merge_pages.py raw/ --out all.jsonl
```

It dedupes on message id and reports per-type counts and the date range, which
is how you notice a page that silently came back empty.

## Phase 4 — Group events into entities

Messages are events. What the user wants to count is usually something else — an
application, an order, a subscription, a conversation.

Two decisions to make explicitly, because both change the headline number:

- **What is the grouping key?** Usually entity plus a detail (company plus role,
  merchant plus item). Normalise both: strip legal suffixes, alias the variants,
  fold `Sr.` into `Senior`.
- **What is the denominator?** "Confirmation emails received" and "distinct
  entity+detail pairs" are different numbers and both are defensible. If they
  differ, publish both and say what each means. Silently picking one is how a
  chart starts lying.

Derive the terminal state per entity — furthest stage reached, not most recent
event — so the categories are mutually exclusive and sum to the total.

## Phase 5 — Anonymise, and check more than the name field

If any of this gets published, pseudonymise. Assign stable pseudonyms in first-
seen order so the mapping is reproducible across rebuilds.

**Then check the free-text fields, because they leak.** This is the trap that
cost the reference run a rebuild: company names hide inside detail strings.
"Senior Software Engineer, Upstart Bank" survives every pseudonym scheme that
only touches the company column.

So scrub brand tokens out of every published free-text field, against the full
entity list — while protecting ordinary vocabulary, or the strings dissolve.
Then verify, don't assume:

```bash
python3 scripts/check_leaks.py private.json public.json \
    --name-field company --check-fields role
```

It cross-references every real name against every published free-text field and
exits non-zero if any survive.

Keep the de-anonymised build out of version control. A `.gitignore` with `raw/`
and the private output is part of the deliverable, not an afterthought.

## Phase 6 — Publish the caveats with the numbers

Mail-derived data has systematic holes, and a dashboard that doesn't name them
is overclaiming. The three that recur:

- **Absence is ambiguous.** "No reply" conflates "they never answered" with
  "they answered and it wasn't labelled". It is an upper bound, not a count.
- **Durations are conditional.** You can only time a response where both ends
  exist. If one side of the pair is often missing, the sample is biased toward
  whichever organisations send both.
- **The archive records correspondence, not effort.** A one-click action and a
  four-hour one look identical.

Watch for the specific bug these produce: when the opening event is missing, the
*response* becomes the first record and the elapsed time computes as zero. In
the reference run this dragged the median from a true 5.0 days down to 1.9. Only
compute a duration when you actually saw the opening event.

## Refreshing later

Never re-run the backfill. Take the newest date in `raw/`, query with a
`newer_than:` bound, write one new page file, re-run the transform. Records
dedupe on message id, so an overlapping window is harmless — prefer overlapping
to missing.

## Reference run

The worked example this skill was extracted from: six years of job-search mail,
three Gmail labels, 1,726 messages → 1,125 applications across 852 companies.

- Live dashboard: <https://thomasrones.com/job-search>
- Write-up, including the prompt used and what it actually cost:
  <https://thomasrones.com/projects/job-search-measured>

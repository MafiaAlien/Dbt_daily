---
description: Blind review, then execute, then three-way compare, then grade Neil's verdict
argument-hint: [day number]
allowed-tools: Read, Write, Edit, Glob, Bash(git log:*), Bash(git status:*), Bash(docker compose:*), Bash(cp:*), Bash(mkdir:*)
---

Day $ARGUMENTS. This command covers Stage 3 and Stage 4. **Run the four phases in
order. Do not read ahead, do not reorder, do not execute anything before Phase 2.**

## Gate

Everything below is derived from files. Neil declares nothing; if a check fails, name the
file and stop.

`days/dayNN/verdict.md` must exist, be **filled in**, and be **committed to git**:

```
git log -1 --format=%H -- days/dayNN/verdict.md
git status --short days/dayNN/verdict.md
```

If it is missing or has uncommitted changes: STOP and say why in Chinese — an
uncommitted verdict can be edited after seeing results, which destroys the scorecard.

`/genprompt` scaffolds an empty skeleton, so **non-empty is not the test.** Read the file
and STOP unless all three hold:

- at least one `### D` block under `Material differences`, with a **Call** that names
  `reference` / `mine` / `equivalent` — not blank, not a description
- `My own solution — where I think it is wrong` has real content
- no unreplaced placeholder (`<one-line title>`, `<list or "none">`, a bare `-`)

A committed skeleton satisfies "exists and committed" while settling nothing. Say plainly
which section is still empty; do not offer partial review in the meantime.

`days/dayNN/reference_solution.md` must also exist and **contain at least one fenced code
block**. `/genprompt` creates it empty, so an empty file means Stage 2 never happened —
STOP and say so. Never fill it yourself, in any phase, for any reason.

## Phase 1 — Blind review (no execution)

Read `days/dayNN/problem.md`, `reference_solution.md`, `verdict.md`, and Neil's solution
under `dbt_practice/models/dayNN/` and `dbt_practice/seeds/dayNN/`.
**Do not read `days/dayNN/.traps.md`. Do not run anything yet.**

Write your own review, severity-ordered:

## Critical
## Major
## Minor
## Style

Each item: what it is, which solution it affects, and the mechanism — not just a verdict.
No praise padding. For anything execution will settle, write
`-> 实跑决定` and move on without arguing it.

## Phase 2 — Execute

Reference first, in its own project — **never** alongside Neil's models: resource names
are unique per project, so two `stg_dNN_*.sql` would fail to parse.

Transcribe the code blocks of `days/dayNN/reference_solution.md` into
`dbt_practice_ref/models/dayNN/…` **verbatim** — original names, no reformatting, no
"obvious" fixes. Editing the reference is how a real bug in it silently disappears
before it can be scored. Then mirror the day's config and data:

```
# dbt_practice_ref/dbt_project.yml already carries the dayNN: block (added by /newday)
cp -R dbt_practice/seeds/dayNN dbt_practice_ref/seeds/dayNN
docker compose exec -w /workspace_ref dbt dbt build --select path:models/dayNN
```

Then Neil's, unchanged:

```
docker compose exec dbt dbt seed  --select path:seeds/dayNN
docker compose exec dbt dbt build --select path:models/dayNN
```

Show both runs' output verbatim, including failing tests. Compare each against the
Expected Output table in `problem.md`, order-insensitive unless the problem specifies
ordering. On a mismatch, query the DuckDB CLI manually before concluding whose code is
wrong — `practice.duckdb` for Neil's, `practice_ref.duckdb` for the reference.

If the reference does not build at all, that is a finding, not a blocker: record it and
carry on to Phase 3.

## Phase 3 — Three-way compare

Now read `days/dayNN/.traps.md`. **This is one of only two places in the repo where that
file may be opened** (the other is `/digest`), and only because phases 1 and 2 just ran
in this conversation. If you arrived here without having run them — a resumed session, a
skipped phase, Neil asking to "jump to the compare" — go back and run them. No file on
disk can authorise this read.

Produce a table: **Neil's solution × reference solution × actual results**, one row per
material difference. For each, state which is correct and by what mechanism.

Then a trap table: each trap -> caught in Neil's code? caught in his review? missed?

## Phase 4 — Grade the review

Score `verdict.md` call by call: right / wrong / not settled. A correct catch of a real
bug in the reference solution is a win — say so plainly. A false alarm and a missed bug
both go to the digest.

Write no state file. Phase 2 already left the evidence `/digest` derives from — the
transcribed models under `dbt_practice_ref/models/dayNN/`. Close with one line in
Chinese: next is `/digest NN`.

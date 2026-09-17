# dbt Daily Practice

A deliberate-practice log for dbt Core. One designed problem per day, each run through a
fixed five-stage workflow, with the reference solution generated blind and a written
review committed before anything is executed.

The SQL here is not the interesting part — a staging view and a fact table are a
morning's work. What this repo is actually about is the failure modes: the metric that
is wrong while every test passes, the row that a `LEFT JOIN` silently invents, the
`sum()` that returns `NULL` where the contract says `0.00`. Each problem is built around
two or three of them on purpose.

## The workflow

Every day moves through five stages in order, and stages are never reordered. There is no
file recording which stage a day is in — the stage is derived from which artifacts exist,
so it cannot drift out of sync with reality or be edited to unlock a step early.

| Stage | What happens |
|---|---|
| **1 — Solve** | Problem is solved alone: models, `schema.yml` tests, materialization config. No hints, no assistance on the modelling itself. |
| **2 — Generate** | A reference solution is produced in a separate, incognito session that has never seen this repository. It is pasted back verbatim — bugs, formatting and all. |
| **3 — Review** | A written code review of the reference, in English, naming every material difference from my own solution and calling which version is correct and why. |
| **4 — Verify** | Both solutions are executed. Reference first, in its own dbt project, transcribed without edits. Then the review is scored call by call: right, wrong, or not settled. |
| **5 — Digest** | Traps are opened, results compared three ways, and takeaways written to `docs/06_key_takeaways.md`. |

Two rules carry most of the value:

**The reference solution is generated blind.** It comes from a conversation that has not
read this repository, so it is independent of how I happened to solve the problem. It is
pasted in verbatim and never touched — editing it to make it build is how a real bug in
it would disappear before it could be found.

**The verdict is committed before anything runs.** An uncommitted review can be quietly
adjusted after seeing the test output, which makes the score meaningless. The verify
command refuses to run until `days/dayNN/verdict.md` is committed to git. Being wrong in
writing, on the record, is the point: a review that only ever agrees with the results
teaches nothing.

Problems are set by an AI agent working from a fixed spec — topic order, difficulty
calibration, and a requirement that at least one trap per day surfaces as a *failing
test* rather than a silently wrong number. The agent is also barred from helping during
Stage 1 and from producing the reference solution, for the reasons above. Every model,
every test, and every review in `dbt_practice/` and `days/*/verdict.md` is mine.

## Environment

dbt Core with DuckDB, in Docker. DuckDB is embedded — no server, no port; the connection
is a file path.

```bash
cp profiles.example.yml profiles.yml
docker compose up -d
docker compose exec dbt dbt build --select path:models/day2
```

There are two dbt projects in one container. `dbt_practice/` is mine, mounted at
`/workspace`. `dbt_practice_ref/` holds the transcribed reference solutions, mounted at
`/workspace_ref` with its own profile and its own DuckDB file:

```bash
docker compose exec -w /workspace_ref dbt dbt build --select path:models/day2
```

The split is not tidiness. dbt resource names are unique per project regardless of
directory, so the reference must run under its original model names with zero edits — it
cannot share a project with mine. Every model and seed carries a day prefix
(`stg_d2_orders`, `fct_d2_region_revenue`) for the same reason, and `ref()` resolves by
name rather than path, so the day folders are for humans, not for dbt.

## Layout

```
days/dayNN/
  problem.md              the problem: grain, per-metric definitions, expected output
  notes.md                my assumptions going in, and the debrief answers coming out
  .traps.md               what the day is really testing; not read until stage 4
  reference_solution.md   pasted verbatim from the blind session
  verdict.md              my review, committed before execution
  digest.md               what the traps caught, and what the review missed
dbt_practice/             my solutions
dbt_practice_ref/         reference solutions, transcribed unedited
docs/06_key_takeaways.md  cumulative, mechanism-level notes
```

Reading one day end to end — `problem.md`, then `verdict.md`, then `digest.md` — shows
the whole loop, including the calls I got wrong.

`docs/06_key_takeaways.md` is written in Chinese with technical terms kept in English. It
is revision material, re-read cold; everything else in the repo is English on purpose,
as interview expression practice.

One file referenced throughout the docs is deliberately absent here:
`docs/05_progress_log.md`, the running scorecard and cumulative blindspot log. It is
kept local — a record of my own recurring mistakes, written for revision rather than for
publication. The workflow specs in `docs/01`–`docs/04` are the design and are published;
the self-assessment is not. Its per-day conclusions do reach this repo, in each
`days/dayNN/digest.md`.

## Days

| Day | Topic | Difficulty |
|---|---|---|
| 1 | staging layer, `ref()` layering, schema tests | Easy |
| 2 | sources vs seeds: `source()`, freshness config, renaming and typing discipline | Easy |
| 3 | materialization trade-offs: view vs table vs ephemeral, and config precedence | Easy–Medium |
| 4 | test design: translating a written data contract into a test suite | Medium |
| 5 | incremental models: `is_incremental()`, `unique_key`, the watermark boundary | Medium |
| 6 | late-arriving data: incremental lookback windows, and what `--full-refresh` does and does not prove | Medium–Hard |

Ongoing.

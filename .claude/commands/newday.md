---
description: Propose and scaffold a new practice day
argument-hint: [day number]
allowed-tools: Read, Write, Edit, Glob, Bash(mkdir:*), Bash(ls:*), Bash(docker compose exec dbt dbt seed:*)
---

Set up Day $ARGUMENTS. If no number was given, use the next unstarted day in
`docs/04_curriculum_backlog.md`.

## Gates — stop and report in Chinese if either fails

1. The previous day's digest is present in the Digest archive of `docs/05_progress_log.md`.
2. The course gating this day's block in `docs/04_curriculum_backlog.md` is marked
   `completed` in `docs/05_progress_log.md`.

## Propose first, then build

Read `docs/04_curriculum_backlog.md` and `docs/05_progress_log.md` (blindspot log
included). Propose the topic, difficulty, and a one-line scenario sketch **in Chinese**,
and wait for Neil to confirm. If a blindspot has repeated, bias the scenario toward
re-exercising it and say so.

## On confirmation, produce

1. Directories: `dbt_practice/models/dayNN/staging`, `.../marts`, and
   `dbt_practice/seeds/dayNN`. Add `intermediate/` only for Medium and above.
2. A `dayNN:` block appended under `models: dbt_practice:` in
   `dbt_practice/dbt_project.yml`. Never remove existing day blocks.
3. `days/dayNN/problem.md` — English, following `docs/02_problem_format_and_templates.md`
   exactly: Problem / Input / Expected Output / Verification / Deliverables / Debrief
   questions. Embed 2-3 traps; at least one must surface as a **failing test** when
   handled naively. At least one debrief question must be a trade-off question.
   Every model and seed name carries the `_dNN_` prefix. `## Deliverables` lists only
   models and schema.yml — **never the seed CSVs**; those are yours (next step).
4. **The seed CSVs themselves**, one file per fenced csv block in `## Input`, written to
   `dbt_practice/seeds/dayNN/`. Byte-for-byte identical to the block: missing values are
   empty fields (no space, no `NULL`, no `""`), one trailing newline at end of file.
   Then load them and show the output verbatim:
   `docker compose exec dbt dbt seed --select path:seeds/dayNN`.
   If the load fails, fix it before handing the day over — Neil must never inherit a
   broken seed.
5. `days/dayNN/.traps.md` — the trap list, with what a naive solution does and which
   test catches it.
6. `days/dayNN/notes.md` — headings `## Assumptions` and `## Debrief answers`.
7. `days/dayNN/STAGE` — containing `1-solve`.

## Close

End with exactly this line, in Chinese, and nothing after it:

**下一步：立刻 `/clear`。traps 现在在我的上下文里，不清掉的话 Solve 阶段我会漏。**

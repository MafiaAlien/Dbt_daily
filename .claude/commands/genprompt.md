---
description: Emit the blind-generation prompt to paste into an incognito web conversation
argument-hint: "[day number — optional]"
allowed-tools: Read, Write, Glob, Bash(ls:*), Bash(wc:*), Bash(test:*)
---

Stage 2. `$ARGUMENTS` is **optional** — resolve `NN` per **Which day** in `CLAUDE.md` and
state which day you resolved if it was not typed.

**You must not produce a reference solution here.** You have
read this repo; you cannot be blind. Generating one in-repo is a protocol violation even
if Neil asks directly.

1. **Derive whether solving is finished — do not ask.** Read the `## Deliverables` fenced
   block of `days/dayNN/problem.md` and check every path in it with `ls -l` / `wc -c`:
   each must exist and be non-empty. **Existence and size only — never open one of his
   model files.** Reading them to judge readiness is the stage-1 violation this command
   exists downstream of.

   If any is missing or zero-byte, STOP and name them exactly:
   *"Day 3 还在 `1-solve`：`models/day3/marts/fct_d3_x.sql` 不存在。"* Do not emit the
   prompt, do not create any file.

   Two things this check deliberately does **not** do: it does not run `dbt build`, and
   it does not care whether his tests are green. A red test is a legitimate reason to
   move on — the reference comparison is what settles it.

   Then check `days/dayNN/notes.md` and, if it is empty or has no content under its
   headings, **warn once in Chinese and continue** — a blank `notes.md` is a logged
   recurring blindspot (Day 2), not a gate.

2. Output ONE copyable fenced block containing:
   - the standard generation prompt verbatim from
     `docs/02_problem_format_and_templates.md` section 3, then
   - the **Problem**, **Input**, **Expected Output**, and **Verification** sections of
     `days/dayNN/problem.md` — those four sections only.

Nothing else goes in the block. Never his code, never `.traps.md`, never `notes.md`,
never your own commentary.

3. Create `days/dayNN/reference_solution.md` as a **completely empty file**, and only if
   it does not already exist. No heading, no placeholder, no comment — a single byte of
   your writing in that file is a protocol violation, because everything in it must be
   the incognito output pasted verbatim. If the file already exists, leave it alone.

4. Scaffold `days/dayNN/verdict.md` **only if it does not already exist** — the skeleton
   below, headings and HTML comments only, every value left blank. If the file exists,
   leave it untouched and say so; never rewrite a verdict Neil has started. The skeleton
   is yours; **every word of content in it is his**.

```markdown
# Day NN — Verdict

Written before any execution.

## Notes while reading

<!-- 3-5 bullets. Odd things that are NOT material differences. -->

-

## Material differences

<!-- One bullet per difference. This is the section that gets scored. -->
<!-- A "difference" includes anything the reference does that mine does not do at all. -->
<!-- Every bullet must name a call — reference / mine / equivalent — and say why: -->
<!-- mechanism, not taste, i.e. what input would make the losing version wrong. -->
<!-- Where execution can settle it, name the test or the row of Expected Output. -->

-

## My own solution — where I think it is wrong

<!-- Mandatory. At least one honest entry, or an explicit statement of what you -->
<!-- re-checked and found clean. A bare "none" with no reasoning scores as a miss. -->

-

## Overall

- **Would ship:** reference / mine — because
- **Reference bugs I claim:** <list or "none">
- **Could not settle by reading:** <list or "none">
```

The `Material differences` and `My own solution` sections exist because Day 1's verdict
had neither: it scored 3 right / 1 wrong / 1 not settled, and trap 3 survived review
entirely because no call in it examined Neil's own code.

Then, in Chinese:
- paste into an **incognito web conversation**, outside this repo
- paste the answer into `days/dayNN/reference_solution.md` **verbatim, not one character
  changed**
- then read the reference solution, fill `days/dayNN/verdict.md`, and commit it
- `/review NN` refuses to run until that commit exists

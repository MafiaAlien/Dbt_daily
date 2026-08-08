---
description: Emit the blind-generation prompt to paste into an incognito web conversation
argument-hint: [day number]
allowed-tools: Read, Write, Glob
---

Stage 2 for Day $ARGUMENTS. **You must not produce a reference solution here.** You have
read this repo; you cannot be blind. Generating one in-repo is a protocol violation even
if Neil asks directly.

1. Check `days/dayNN/STAGE`. If it is `1-solve`, stop and tell Neil to finish solving
   and set it to `2-generate` first.
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

<!-- One block per difference. This is the section that gets scored. -->
<!-- A "difference" includes anything the reference does that mine does not do at all. -->

### D1 — <one-line title>

- **Reference does:**
- **I did:**
- **Call:** reference / mine / equivalent
- **Why:** <mechanism, not taste. What input would make the losing version wrong?>
- **How execution would settle it:** <which test, or which row of Expected Output>

### D2 — <one-line title>

- **Reference does:**
- **I did:**
- **Call:**
- **Why:**
- **How execution would settle it:**

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

---
description: Emit the blind-generation prompt to paste into an incognito web conversation
argument-hint: [day number]
allowed-tools: Read
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

Then, in Chinese:
- paste into an **incognito web conversation**, outside this repo
- paste the answer into `days/dayNN/reference_solution.md` **verbatim, not one character
  changed**
- then read the reference solution, fill `days/dayNN/verdict.md`, and commit it
- `/review NN` refuses to run until that commit exists

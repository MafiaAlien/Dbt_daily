# dbt Daily Practice Workflow v1

Adapted from the PySpark practice template v2. Five stages, run in order.
One problem per day; a day may span multiple sessions but stages must not be reordered.

## Stage 1 — Solve (Neil, alone)

- Read the problem file. Set up seeds, write models, schema.yml tests, and
  materialization config in the local Docker + DuckDB environment.
- Allowed references: official dbt docs (docs.getdbt.com) and DuckDB docs.
- Not allowed: asking Claude for hints, searching for the specific problem pattern's
  full solution.
- It is OK (and expected) to run `dbt seed` / `dbt run` / `dbt test` iteratively while
  solving — Verify in Stage 4 refers to verifying the *reference* answer, not a
  first-run ban on Neil's own code.
- Output: working solution committed in the practice repo, plus written answers (in
  English) to the Debrief questions — drafted now, refined after Verify.

## Stage 2 — Generate (incognito, outside this project)

- Purpose: produce a reference solution that is independent of Neil's solution and of
  this project's memory.
- Neil opens an **incognito conversation** (not in this project), pastes the standard
  generation prompt (see `02_problem_format_and_templates.md`) together with the
  Problem / Input / Expected Output / Verification sections ONLY — never his own code.
- Copy the generated reference solution back into this project's chat verbatim.

## Stage 3 — Review (Neil first, then Claude)

- Neil performs a written code review of the reference solution in English:
  line-level comments, then an overall **verdict**: for each material difference from
  his own solution, state which version is correct/better and why.
- The verdict must be committed in writing BEFORE anything is executed.
- Claude then reviews both solutions and Neil's verdict, prioritized by severity
  (Critical → Major → Minor → Style). Claude does not reveal trap outcomes that
  execution will settle — disputes that `dbt build` can adjudicate are left to Stage 4.

## Stage 4 — Verify (execution)

- Run the reference solution in the local environment: `dbt seed` → `dbt build`.
- Compare against Expected Output (a `check` query or `dbt test` suite decides; use
  order-insensitive comparison where ordering is not specified).
- Score the Review: which of Neil's verdict calls were right/wrong? A correct catch of
  a real bug in the reference answer is logged as a win; a missed bug or a false alarm
  is logged for Digest.

## Stage 5 — Digest (Claude produces, Neil archives)

Claude outputs a Digest block in exactly this format, and Neil appends it to
`05_progress_log.md`:

```
### Day N — <topic> (<date>)
- Problem: <one line>
- Traps: <each trap, and whether Neil's solution / review caught it>
- Verdict scorecard: <right calls / wrong calls in Review>
- Key takeaways: <max 3 bullets, mechanism-level, interview-quotable>
- Recurring-pattern check: <does any mistake match a prior day's? cite the day>
- Parking lot additions: <deferred topics + one-sentence summary each>
```

## Session hygiene

- Start each session by stating the current Day number and stage.
- If a stage was completed in a previous session, paste or summarize its output rather
  than relying on memory.
- Do not start Day N+1 before Day N's Digest is appended to the progress log.

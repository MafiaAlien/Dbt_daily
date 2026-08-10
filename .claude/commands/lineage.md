---
description: Prove a day's DAG has no cross-day contamination
argument-hint: [day number]
allowed-tools: Read, Glob, Bash(docker compose:*), Bash(grep:*), Bash(git log:*), Bash(git status:*), Bash(ls:*)
---

Day $ARGUMENTS. Verify the day's models depend only on that day's resources.

`ref()` resolves by **resource name, not directory**. Putting files in `models/dayNN/`
guarantees nothing — a typo'd `ref('stg_d2_orders')` inside a day-3 model compiles
cleanly and runs, because d2 exists. dbt reports no error; the answer is just wrong.
This command is the check that catches it.

1. List every upstream node of the day's marts:
   `docker compose exec dbt dbt ls --select +path:models/dayNN`
2. Upstream seeds specifically:
   `docker compose exec dbt dbt ls --select +path:models/dayNN --resource-type seed`
3. Grep every `ref(` and `source(` under `dbt_practice/models/dayNN/`.

Report in Chinese:
- Any node in the upstream closure whose name does not carry `_dNN_` -> **flag it**
- Any seed under `seeds/dayNN/` that appears in no model's upstream -> unused seed,
  usually means a `ref()` typo or a model that was never written
- Otherwise: clean, one line

**Stage discipline — derived, and deliberately conservative.** Full commentary is
unlocked only once `days/dayNN/verdict.md` is filled in **and committed**
(`git log -1 --format=%H -- days/dayNN/verdict.md` non-empty and `git status --short`
clean for it) — that is, state ≥ `4-verify` in the `CLAUDE.md` derivation table.

Until then — including the whole window after he has written his models but before the
verdict is committed — report **only** the raw node lists and the name-prefix mismatches.
Do not say which model has the wrong `ref()`, do not comment on the shape of the DAG, do
not hint at whether the lineage looks right for this problem. Structural check only.

The gate hangs on the *verdict commit* rather than on "his files exist" on purpose:
existing files prove he started, not that he finished, and a lineage comment delivered
mid-solve is a hint. Fail closed.

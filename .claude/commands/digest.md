---
description: Write the digest and update the logs — the only command that writes logs
argument-hint: [day number]
allowed-tools: Read, Write, Edit, Bash(ls:*)
---

Day $ARGUMENTS, Stage 5.

**Precondition, derived — do not ask.** `dbt_practice_ref/models/dayNN/` must contain at
least one `.sql` file: that is the residue of `/review` phase 2, and the only proof on
disk that the reference was actually executed. If the directory is missing or empty,
STOP — say in Chinese that `/review NN` has not run and there is nothing to digest.

A digest written without a review is a fabricated scorecard. There is no partial version
of this command.

**This is the only command permitted to write to `docs/05_progress_log.md` and
`docs/06_key_takeaways.md`.** No other command touches them.

Read `days/dayNN/problem.md`, `.traps.md`, `verdict.md`, `notes.md`, and the cumulative
blindspot log plus parking lot in `docs/05_progress_log.md`.

Produce the digest block in EXACTLY this format, in English:

```
### Day N — <topic> (<date>)
- Problem: <one line>
- Traps: <each trap, and whether Neil's solution / review caught it>
- Verdict scorecard: <right calls / wrong calls in Review>
- Key takeaways: <max 3 bullets, mechanism-level, interview-quotable>
- Recurring-pattern check: <does any mistake match a prior day's? cite the day>
- Parking lot additions: <deferred topics + one-sentence summary each>
```

Key takeaways must be mechanism-level and quotable in an interview. "ref() resolves by
name, not path — directories are for humans" is good. "Be careful with joins" is not.

For `Recurring-pattern check`, compare against every prior digest and the blindspot log.
If a mistake repeats, name the prior day. On a second repeat, escalate: sharpen or add
the blindspot entry.

Then write, in this order:

1. `days/dayNN/digest.md`
2. Append the block to the Digest archive in `docs/05_progress_log.md`
3. Fill the Day N row of the Practice days table (topic, difficulty, date, scorecard, result)
4. Append the Key takeaways bullets to `docs/06_key_takeaways.md` under a
   `## Day N — <topic>` heading — one line each, no prose around them
5. Add any new blindspot rows and parking-lot rows

Write no state file. Step 1 and step 2 together are what make the day derive as `done`.

Close in Chinese with: which day is now unlocked, and

**`git diff docs/06_key_takeaways.md` — 十秒，只看新增行。**

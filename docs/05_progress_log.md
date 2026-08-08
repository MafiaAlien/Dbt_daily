# Progress Log (living document — Neil updates after every day)

## Course progress

| dbt Learn course | Status | Completed on |
|---|---|---|
| dbt Fundamentals | completed | 2026-07-25 |
| Incremental Models | in progress | |
| Snapshots / SCD | not started | |
| Jinja, Macros & Packages | in progress | |
| Advanced Testing | not started | |

## Practice days

| Day | Topic | Difficulty | Date | Verdict scorecard | Result |
|---|---|---|---|---|---|
| 1 | staging + ref + tests | Easy | 2026-07-28 | 3 right / 1 wrong / 1 not settled | Trap 3 hit (`count(*)` under LEFT JOIN), tests green throughout; committed version did not compile; green and matching expected output after fixes |
| 2 | sources vs seeds: `source()`, freshness, typing discipline | Easy | 2026-08-07 | 3 right / 3 wrong / 0 not settled | All 5 traps handled in code; 19/19 green and Expected Output matched row-for-row on the first run, in both projects. Two latent defects went unnoticed by the test suite and by his own review: helper column `rn` published out of `stg_d2_orders` (8 columns where the contract says 7), and a single-layer NULL defence on `gross_revenue_usd`. `notes.md` left entirely blank |

## Digest archive

(Append each day's Digest block here, newest at the bottom.)

### Day 1 — staging layer + ref() layering + schema tests (2026-07-28)
- Problem: build two staging views 1:1 over seeds and one mart table at customer grain, where order_count and total_amount must be 0 rather than null for customers with no orders or no captured amounts.
- Traps: (1) `sum()` over an all-null group returns null — avoided, but by accident: a `case when status = 'completed' then amount else 0 end` that was itself a requirements miss happened to supply the zero; not identified in review. (2) driving the mart from orders instead of customers — avoided, mart was customer-driven from the start; not discussed in review. (3) `count(*)` under a LEFT JOIN counting the unmatched row — **hit**, Dan Wu scored 1 order instead of 0 while all 11 schema tests passed; missed in review as well.
- Verdict scorecard: 3 right / 1 wrong / 1 not settled. Right: reference is the version to ship, reference contains no bugs (confirmed — 14/14 green, output matches expected exactly). Wrong: "could not settle by reading: none", contradicted by his own bullet admitting uncertainty. Not settled: read the reference's pre-aggregate-then-join shape as a performance question when the two `coalesce` calls in it are a correctness measure. No call in the verdict examined his own code, which is why trap 3 survived the review.
- Key takeaways:
  - 一个组里全是 NULL 时，`count(expr)` 返回 **0**，`sum(expr)` 返回 **NULL** —— 正是这个不对称决定了 `order_count` 不需要 `coalesce` 而 `total_amount` 必须要。
  - LEFT JOIN 之下，`count(*)` 数的是没匹配上的那行占位行，`count(<child key>)` 数的才是真实子记录;`unique` / `not_null` 都区分不出这两者，只有比对 expected output 才发现得了。
  - dbt 内置的 `relationships` test 编译时会在 child CTE 里加一句 `where <column> is not null`：它断言的是"出现的非空值必须在 parent 中存在"，**从不**断言"值必须存在"。
- Recurring-pattern check: trap 3 is a direct repeat of the carry-in blindspot "[modeling] NULL-exclusion bugs silently dropping rows from rate calculations" — same mechanism (null handling across a join quietly mis-stating a metric), new surface (mis-counted rather than dropped). Escalated: the blindspot entry is sharpened to name the LEFT JOIN counting case. Second pattern, new this day: verifying something other than what was committed — `dbt build` was reported green while the committed mart contained `group by 1, xss2`, which cannot compile. Third: debrief question 3 answered "got no idea about this topic", which is the logged "[general] deferring a topic without extracting a one-sentence summary" pattern applied to his own deliverable.
- Parking lot additions: seeds vs sources — a seed is a dbt-owned table built from a CSV in the repo and referenced with `ref()`, while a source is a table dbt does not build, declared in a `sources:` block and referenced with `source()`; deferred during stage 1-solve because answering it would have settled a Day 1 modelling decision.

### Day 2 — sources vs seeds: source(), freshness config, renaming/typing discipline (2026-08-07)
- Problem: declare an ERP export as a `source` (never `ref()` it), dedup it to one row per `order_id` on the latest `EXPORTED_AT`, normalise a dirty status column, and roll orders up to one row per region present in staging — with unmapped countries landing in an `'Unmapped'` row and a mapped-but-unused country producing no row at all.
- Traps: (1) re-exported order 5003, grain — **caught in code** (`row_number() over (partition by order_id order by exported_at desc)`, correct direction, 11 rows); missed in review, D2 discussed where the ranking lives but never why the dedup *direction* matters. (2) status casing and whitespace — **caught in code** (`lower(trim(...))`, both halves present); missed in review, D1 touched `order_status` but argued cast placement instead. (3) unmapped `JP` → `'Unmapped'` — **caught in code** (left join + coalesce, correct direction); **caught in review** (D3, called equivalent, correct). (4) which side drives the mart, `MX → LATAM` must not appear — **caught in code** (orders-driven, 4 rows); missed in review. (5) Day 1 recurrence, APAC's `sum()` over an empty completed set — **caught in code**, but via a blanket `else 0` applied identically to the count and the sum, which is the signal the `count`/`sum` asymmetry is not yet internalised; missed in review.
- Verdict scorecard: 3 right / 3 wrong / 0 not settled. Right: D3 `'Unmapped'` coalesce placement is equivalent (confirmed, row-for-row identical); "would ship the reference"; "reference bugs I claim: none" (confirmed — 19/19 green, output matches Expected Output exactly, no false alarm). Wrong: D1 claimed the reference's inner cast is better, execution says equivalent and the stated mechanism does not hold — the seeded column is already VARCHAR; D2 called the `row_number` placement equivalent, but the reference's explicit 7-column final select is precisely what drops the helper column, and his `select *` leaks `rn` into a model the problem specifies as 7 columns; "could not settle by reading: none" while three fields in the same file read "no clue". Two material differences never appeared in the verdict at all: `count(case…end)` vs `sum(case…else 0 end)`, and the reference's two-layer NULL defence on `gross_revenue_usd` vs his single layer. The `My own solution — where I think it is wrong` section, added after Day 1 for exactly this purpose, produced a style preference rather than either of the two real defects sitting in his own code.
- Key takeaways:
  - `sum(case when cond then x end)` 的 NULL 有**两个**来源，要两层 `coalesce`：内层 `coalesce(x, 0)` 补的是单行里缺失的值，外层 `coalesce(sum(...), 0)` 补的是整组没有一行满足 cond。`then x else 0` 只挡得住后者——一旦某组全部满足 cond 且 `x` 全为 NULL，`sum` 照样返回 NULL。
  - staging 模型最后一句写 `select *`，会把去重用的 helper 列（`row_number` 的 `rn`）一起发布出去；模型契约说 7 列，实际 8 列，而 `unique` / `not_null` / `accepted_values` **没有一个**检查列的集合。排名放在哪个 CTE 都行，最终 select 必须逐列重列。
  - source 不是 dbt 建的 node：`source()` 在 DAG 上没有上游边，`--select path:models/dayNN` 不会重建它，上游坏了 dbt 也不会告诉你——`dbt source freshness` 是唯一的哨兵。同理，`unique` 该挂在去重后的 staging model 上而不是 source 上：test 挂在 source 上断言的是**上游系统的保证**，挂在 model 上断言的是**这个模型自己的保证**。
- Recurring-pattern check: three repeats, two of them escalated. (1) "Could not settle by reading: none" written alongside his own admissions of uncertainty — a verbatim repeat of Day 1's single wrong call; second occurrence, blindspot sharpened. (2) The verdict again settled nothing about his own code: Day 1's logged pattern was "[dbt] reviewing one's own solution only against the reference's style, never comparing outputs", and the dedicated `My own solution` section introduced in response to it was filled with a style preference while two real defects went unnamed; second occurrence, blindspot sharpened. (3) `days/day2/notes.md` was left entirely blank — no assumptions, no `dbt source freshness` output, none of the four debrief answers — which is the logged "[general] deferring a topic without extracting a one-sentence summary" pattern escalated from one skipped question on Day 1 to a whole skipped deliverable. Counterweight worth stating plainly: the code itself hit all five traps, built green in both projects, and matched Expected Output row-for-row on the first run. The gap is entirely on the review side.
- Parking lot additions: none new. Day 1's `seeds vs sources` row is resolved by this day and closed. Day 2's four debrief questions are **not** parked — they are unwritten deliverables, and the `warn_after` / `error_after` orchestration semantics in question 4 stay unanswered until `notes.md` is filled.

## Cumulative blindspot log

Recurring error patterns across ALL practice tracks (carry-ins from PySpark and
dimensional modeling included, so cross-domain repeats are visible):

- [modeling] Editing schema correctly but leaving contradictory statements in earlier
  analysis sections → checklist sync step required
- [modeling] NULL-exclusion bugs silently dropping rows from rate calculations —
  **sharpened Day 1:** also covers null-padded rows being *counted*, not just dropped;
  `count(*)` over a LEFT JOIN scored a customer with zero orders as 1, and no schema
  test fires on it
- [general] Deferring a topic without extracting a one-sentence summary first —
  **repeat Day 1:** debrief question 3 left as "got no idea about this topic";
  **escalated Day 2:** the whole of `notes.md` left blank — no assumptions, no
  `dbt source freshness` output, none of the four debrief answers. The pattern grew
  from one skipped question to an entire skipped deliverable
- [general] Missing ambiguous quantifiers in requirements as prompts for clarification
- [dbt] Reviewing one's own solution only against the reference's style, never
  comparing outputs — Day 1 verdict contained no call about his own code, so the one
  trap he hit went unnoticed. **Escalated Day 2:** a dedicated `My own solution — where
  I think it is wrong` section was added to the verdict skeleton in response, and its
  first use produced a style preference ("split some cast steps") while both real
  defects — the leaked `rn` column and the single-layer NULL defence — sat unnamed in
  his own files. The section is not the fix; comparing *what the two versions produce*
  is
- [dbt] Writing "could not settle by reading: none" in the same verdict that says
  "no clue" elsewhere — Day 1 wrong call, **repeated verbatim Day 2** (three fields).
  Uncertainty admitted anywhere in the file belongs in that line; it is the one call
  that costs nothing to get right
- [process] Reporting a run as green without running the state that was committed —
  Day 1 `dbt build` claimed green while the committed mart could not compile

## Parking lot (deferred topics, each with a one-sentence summary)

| Topic | One-sentence summary | Deferred on | Revisit when |
|---|---|---|---|
| dbt state / deferral | CI optimization that builds only changed models by comparing manifests | project setup | Block 5 Day 13 |
| seeds vs sources | A seed is a dbt-owned table built from a repo CSV and referenced with `ref()`; a source is a table dbt does not build, declared in a `sources:` block and referenced with `source()` | Day 1, stage 1-solve | **Closed Day 2** — exercised as that day's topic |

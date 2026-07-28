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
  **repeat Day 1:** debrief question 3 left as "got no idea about this topic"
- [general] Missing ambiguous quantifiers in requirements as prompts for clarification
- [dbt] Reviewing one's own solution only against the reference's style, never
  comparing outputs — Day 1 verdict contained no call about his own code, so the one
  trap he hit went unnoticed
- [process] Reporting a run as green without running the state that was committed —
  Day 1 `dbt build` claimed green while the committed mart could not compile

## Parking lot (deferred topics, each with a one-sentence summary)

| Topic | One-sentence summary | Deferred on | Revisit when |
|---|---|---|---|
| dbt state / deferral | CI optimization that builds only changed models by comparing manifests | project setup | Block 5 Day 13 |
| seeds vs sources | A seed is a dbt-owned table built from a repo CSV and referenced with `ref()`; a source is a table dbt does not build, declared in a `sources:` block and referenced with `source()` | Day 1, stage 1-solve | Day 2 (its stated topic) |

# Day 7 — notes

## Interval plan

<!-- Written BEFORE any SQL. Four lines, per ## Deliverables in problem.md.
     1. The full predicate for "version in effect at order_ts", both boundary operators
        and the dbt_valid_to is null case.
     2. tier_at_order / region_at_order / current_tier — which relation, which join.
     3. How many snapshot rows can match one stg_d7_orders row, and what makes it 1.
     4. The two order_ids your predicate decides, and what each becomes if you flip an
        operator. -->

1. boundary min <= order < max

## Snapshot config decisions

<!-- strategy, unique_key, updated_at, and where each is configured.
     Why YAML and not the legacy {% snapshot %} block.
     What dbt_valid_from is set to on a FIRST version under your strategy. -->
     strategy: timestamp
     unique_key: account id
     updated_at: updated_at,
     dbt_valid_from is set by updated_at for first version

## Test count

<!-- assertions V1-V11 ask for: N
     dbt ls --resource-type test --select path:models/day7 path:snapshots/day7 path:tests/day7 --quiet | wc -l : N
     if they ever differed: what the difference was -->
36

## Assumptions

## Run log

<!-- The Done. PASS=… WARN=… ERROR=… SKIP=… line from all three builds, plus the five
     captured tables. Pasted, not summarized. -->

## Debrief answers

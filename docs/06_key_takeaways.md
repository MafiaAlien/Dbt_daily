# Key Takeaways (cumulative)

Written by `/digest` only, one section per day, bullets only — no prose.
Mechanism-level and interview-quotable, or it does not belong here.

Review ritual: after each `/digest`, run `git diff docs/06_key_takeaways.md` and read
only the new lines. Ten seconds.

## Day 1 — staging layer + ref() layering + schema tests

- 一个组里全是 NULL 时，`count(expr)` 返回 **0**，`sum(expr)` 返回 **NULL** —— 正是这个不对称决定了 `order_count` 不需要 `coalesce` 而 `total_amount` 必须要。
- LEFT JOIN 之下，`count(*)` 数的是没匹配上的那行占位行，`count(<child key>)` 数的才是真实子记录;`unique` / `not_null` 都区分不出这两者，只有比对 expected output 才发现得了。
- dbt 内置的 `relationships` test 编译时会在 child CTE 里加一句 `where <column> is not null`：它断言的是"出现的非空值必须在 parent 中存在"，**从不**断言"值必须存在"。
- 钱一律用 `decimal(p,s)` 不用 `double`：`decimal` 是十进制定点、精确，`double` 是二进制浮点，`0.1 + 0.2 = 0.30000000000000004`;且聚合会加宽 precision，mart 层要 `cast` 回契约声明的类型。

## Day 2 — sources vs seeds: source(), freshness config, renaming/typing discipline

- `sum(case when cond then x end)` 的 NULL 有**两个**来源，要两层 `coalesce`：内层 `coalesce(x, 0)` 补的是单行里缺失的值，外层 `coalesce(sum(...), 0)` 补的是整组没有一行满足 cond。`then x else 0` 只挡得住后者——一旦某组全部满足 cond 且 `x` 全为 NULL，`sum` 照样返回 NULL。
- staging 模型最后一句写 `select *`，会把去重用的 helper 列（`row_number` 的 `rn`）一起发布出去；模型契约说 7 列，实际 8 列，而 `unique` / `not_null` / `accepted_values` **没有一个**检查列的集合。排名放在哪个 CTE 都行，最终 select 必须逐列重列。
- source 不是 dbt 建的 node：`source()` 在 DAG 上没有上游边，`--select path:models/dayNN` 不会重建它，上游坏了 dbt 也不会告诉你——`dbt source freshness` 是唯一的哨兵。同理，`unique` 该挂在去重后的 staging model 上而不是 source 上：test 挂在 source 上断言的是**上游系统的保证**，挂在 model 上断言的是**这个模型自己的保证**。


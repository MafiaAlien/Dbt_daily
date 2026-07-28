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


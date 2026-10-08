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

## Day 3 — materialization trade-offs: view vs table vs ephemeral, config precedence

- 维度计数必须在**维度自己的 grain 上聚合完**再 left join 事实表。`subscriptions left join usage_events` 之后的 CTE，grain 已经是 (订阅×事件)，此时 `count(*)` 数的是 join 行数，每个订阅按它的事件条数被放大；`sum(case when status='active' then 1 else 0 end)` 同样被放大。正确形状是两段式：先 `group by plan_code` 把订阅聚成一行，再把用量聚合 left join 上去 —— 一次 join 只允许一边是"多"。
- boolean 列上写 `x is not null` 是**空值检查**，不是真值检查；只要该列非空（而 `not_null` test 正保证了它非空），这个谓词恒为真，一行都滤不掉。要过滤真值只有 `where x` 或 `x is true`。同理 `count(x)` 跳过 NULL 而 `count(*)` 不跳 —— 谓词和聚合函数各有各的 NULL 语义，不能靠一条统一规则覆盖。
- materialization 优先级：in-model `{{ config() }}` > `dbt_project.yml` 里更具体的路径 > 更一般的路径 > 项目默认。同一个目录里要两种物化时，目录级 config 表达不了，只能用 in-model override —— 这是它唯一正当的用途。反过来，在**每个**模型里都写死 config，会让一次有意的项目级变更（比如把所有 marts 改成 incremental）静默失效：你以为改了，实际一个都没生效。

## Day 4 — test design: translating a written data contract into a test suite

- 四个内置 generic test 里，只有 `not_null` 回答"值在不在"，其余三个只回答"值对不对"，且排除 NULL 的机制不同：`unique` 和 `relationships` 的编译产物里**明写**着 `where <column> is not null`（前者不让 NULL 参与唯一性，后者只断言"出现过的值必须在 parent 存在"），而 `accepted_values` 靠三值逻辑 —— `NULL not in ('A','B')` 求值为 NULL 而非 TRUE，被 `WHERE` 挡掉。所以一列的完整合约通常要拆成两个断言，而且两个断言可以有各自的 severity：同一列上 `not_null` 设 warn（已知缺陷、必须报不许拦）+ `accepted_values` 留 error（真出现非法值就 fail）。
- `severity` 是天花板，不是默认值。dbt 源码 `task/test.py` 里判定只有一条路径能 fail：`if severity == "ERROR" and result.should_error`。所以 `severity: warn` 配上 `error_if: ">10"`，`error_if` 被完全架空，永远最多是 WARN;阈值写法必须建立在 `severity: error` 之上（`severity: error` + `warn_if: ">0"` + `error_if: ">10"`）。另外 severity 只在测试**返回了行**之后才被咨询 —— 返回 0 行时 error 和 warn 没有任何区别，改 severity 治不了"测试根本抓不到这一行"。
- 自定义 generic test 的**目录决定了 dbt 怎么解释这个文件**：定义只在 `macros/` 和 test-path 根下的 `generic/`（即 `tests/generic/`）被识别，放进 `tests/dayNN/generic/` 这样深一层的目录不算。放错的后果有两层，且都不在 parse 阶段暴露 —— 文件被当成 singular test，`{% test %}` 块只是定义、不输出任何文本，渲染成空字符串后被塞进 `select ... from ( ) dbt_internal_test`，报 `syntax error at or near ")"`；同时每一条引用它的断言在**执行**时各自变成一个 `'test_xxx' is undefined` 的 Compilation Error。`dbt compile` 打出空的编译产物，就是这个形状的指纹。

## Day 5 — incremental models: is_incremental(), unique_key, and the watermark boundary

- `is_incremental()` 是 **Jinja 宏,编译期求值**,数据库全程没参与判断 —— `{% if %}` 决定的是编译产物里**有没有那段 where 文本**,run 1 和 run 2 发给引擎的是两份不同的 SQL(所以 `grep 'ship_date >=' target/compiled/...` 是它到底生效没有的唯一硬证据,读源码不算)。四个条件全真才返回 True：目标 relation 存在、且 `relation.type == 'table'`(存的是 view 就走全量,防物化切换错配)、模型 config 是 `incremental`、且 `not should_full_refresh()`(同时看 `--full-refresh` 和模型自己的 `full_refresh: false`)。外层还有一道 `{% if not execute %}` 短路：dbt 一条命令渲染模型两遍,parse 阶段 `execute=False` 且禁止 introspective query,直接返回 False —— 所以**它只能切换 SQL 里的过滤逻辑,不能用来切换 `ref()`**,否则 DAG 在 parse 期就建错了。
- `>` 和 `>=` 不是风格选择,它和 `unique_key` 是**互相担保**的一对:`>=` 只有在 `unique_key` 存在时才安全(重算的行被 delete+insert 替换掉),没有 key 就退化成 append、同一个 (date, warehouse) 插两遍;`>` 只有在没有 key 时才"安全",而那时它已经因为别的原因是错的。水位线那天**恰恰是还没结账的那天** —— feed guarantee 只承诺新批次不带来更早的 `ship_date`,没承诺不带来**相等**的,而相等正是要命的情况:写 `>` 会把 2026-06-03 冻结在 run 1 的值上,少一行、错两行,**六个测试全绿**。唯一抓得住它的是逐格比对 run 2,以及 `--full-refresh` 等价校验 —— 而等价校验只在模型真的有增量谓词时才有鉴别力,没有守卫的模型两边跑的是同一件事,它永远通过。
- 增量过滤的对象是**"需要重算的键",不是"新到的行"**。谓词要加在覆盖全量历史的上游 view 上,`ship_date >= watermark` 选中一天之后,这一天要用**全部** feed 重算(06-03 的 S008 来自 batch 1、S010 来自 batch 2,必须一起进 `sum`);换成 `where batch_id = 2` 算出来的是残缺结果,再盖到旧行上,那一天就废了。配套的两件事:`max(ship_date) from {{ this }}` 外面要包 `coalesce(..., 哨兵日期)`,因为空表时 `max()` 返回 NULL 而 `ship_date >= NULL` 求值为 NULL 不是 TRUE,会安静地产出空表 —— `is_incremental()` 只保证表**存在**,不保证**非空**;`unique_key` 必须就是模型声明的 grain,写成别的列在 `delete ... using` 绑定阶段直接炸,写成 grain 的子集则会误删。

## Day 6 — late-arriving data: incremental lookback windows and `--full-refresh` equivalence

- - `schema.yml` 里的 model name 是**按名字绑定**的，绑不上时 dbt 发的是 **WARNING 不是 ERROR** —— `Did not find matching node for patch with name 'x'`，然后那个 model 下面挂的所有 generic test 会因为依赖一个不存在的节点而被静默丢弃，`dbt build` 照样 `WARN=0 ERROR=0` 全绿。**「测试没注册」和「测试跑了且通过」在 `Done. PASS=…` 这一行里是同一个样子**，差别只在总数上。所以绿灯不是证据，**节点数才是**：`dbt ls --resource-type test --select path:models/dayNN | wc -l` 数一遍，或者把 `dbt parse` 的 warning 当错误读（本次它连喊了 9 遍）。这一天 23 vs 39 的差距就是这么来的，而且丢掉的恰好是题目专门设计来考「write-once feed 该不该加 unique」的那 8 个。
- - 对账测试（reconciliation）必须用 **`full outer join`**，`left join` 只能覆盖一个方向，而且是**不重要**的那个方向。机制在 NULL 的三值逻辑：mart 缺整行时 join 出来的 `delivery_count` 是 NULL，`stg_cnt <> NULL` 求值为 **NULL 而不是 TRUE**，`where` 只保留 TRUE，于是那一行被丢掉 —— 一个「mart 从来没写过的行」对任何从 mart 出发、或用 `<>` 比较的测试都是**不可见**的，而那正是增量模型最典型的坏法（漏算一天）。再加一条 `mart_row_count <> 1`，「恰好一行」才和「唯一性」解耦。顺带：`from a, b where …` 少写 join 条件不会报错，只会变成笛卡尔积，失败行数是 **n²−n** —— 看到 2 / 42 / 90 对应 2 / 7 / 10 行的表，不用查就知道是缺了 join 谓词。
- - 增量回看窗口（lookback window）的宽度**从 SLA 推导，不是拍的**：「最晚迟到 4 个日历日」+「delivery_date 不会晚于自己的 load date」⇒ 任何新到行都满足 `delivery_date >= L-4`，而 mart 的 `max(delivery_date) <= L`，所以 `max - 4` 一定在安全线之下。推完之后 **`>` 和 `>=` 就不是风格问题**：SLA 给的是闭区间，写 `>` 等于把窗口从 4 天缩成 3 天，恰好丢掉边界那一天。本次数据里 2/3/4 天宽都能算对，所以**测试全绿、逐格比对也全对，错误依然存在** —— 这类「数据惩罚不到的规格违反」只能靠读代码抓，不能靠跑。窗口选的是**「哪几天要重算」而不是「哪些行是新的」**，选中之后那几天要用全量上游重算，再用 `delete+insert` 整段替换。

## Day 7 — snapshots: timestamp strategy, `dbt_valid_from` / `dbt_valid_to`, point-in-time attribution

- As-of join 的谓词是 `order_ts >= dbt_valid_from and (dbt_valid_to is null or order_ts < dbt_valid_to)`：半开区间，写在 **LEFT JOIN 的 ON** 里，三个零件各防一个坑。`>=` / `<` 保证内部边界上的订单只落进**后一个**版本；`between` 两端都闭，会在边界上一行变两行，钱跟着翻倍。`is null` 分支是因为 `ts < NULL` 求值为 NULL 而不是 TRUE，不写它，当前（open）版本永远匹配不上。LEFT JOIN 是因为 timestamp strategy 下第一个版本的 `dbt_valid_from` 是它自己的 `updated_at`，**不是时间起点**，早于它的订单用 inner join 会整行消失。另外，SQL 没有链式比较，`a <= b < c` 不是区间判断。
- Snapshot 不读版本流：它每次运行比较的是 **relation 的当前状态**和已存的历史。所以 relation 必须每个 `unique_key` 恰好一行；同一批次里被覆盖掉的中间版本永远进不了历史（A200 PREMIUM 丢失，O-006 于是归到 STANDARD），**历史的分辨率就是运行频率**。timestamp strategy 下窗口边界取源系统的 `updated_at` 而不是运行时间，所以窗口表示的是业务时间。它还是项目里**唯一不能从源重建**的表：`select *` 带进去的 `_rn` 会永久留在表结构里。
- 测试如果复用了模型的谓词，就会继承模型的 bug：V10 和 fct 用的是同一句 `order_ts < dbt_valid_to`，对 open 版本同时失明，模型错了测试照样返回 0 行。intent test 要**独立推导**（reference 的 V10 自己重写了带 `is null` 的覆盖判断），并且至少要在一份故意弄坏的数据上看它红一次。同理，dbt 1.12 里 singular test `ref()` 了不存在的模型、`schema.yml` patch 名拼错，都只是 parse 阶段的 WARNING 加静默禁用；`Done.` 行里的 `WARN=` 只数 node 结果，不数 parse warning，所以 32 vs 39 只有 `dbt ls | wc -l` 能看出来。

## Day 8 — snapshots, part two: `check` vs `timestamp`, `hard_deletes: new_record`, current-view dim on a snapshot

- `hard_deletes` 三个值决定"离职"在 snapshot 里长什么样：`ignore`（默认）对消失视而不见，open 行永远像在职；`invalidate` 只把窗口关掉，不写行、没有 `dbt_is_deleted` 列，离职无法计数；`new_record` 复制最后一版写一行终止记录，`dbt_valid_from` = 运行时间，**`dbt_valid_to` = NULL**。所以在 `new_record` 下终止记录**本身就是 open 行**，Day 7 的 "current = `dbt_valid_to is null`" 在这里是错的，正确谓词是 `dbt_valid_to is null and dbt_is_deleted <> 'True'`（而"每个 key 恰好一行 open"依然成立，离职的人也是）。rehire 会关掉终止行、插入新版本，即使 tracked 列完全相同。`dbt_is_deleted` 是 VARCHAR `'True'` / `'False'`，不是 boolean：比较写字符串，并在 int 层一次性转成真 boolean，marts 只看 `is_deleted` / `is_current`。
- `check` 策略 + `check_cols` 只列 tracked 列 + 不设 `updated_at`：当且仅当 tracked 列变化才出新版本，`dbt_valid_from` 取 `snapshot_get_time()` 运行时间。用 `record_updated_at` 做 timestamp 会漏掉不碰它的批量脚本、又把姓名修正版本化；`check_cols: all` 会因为 `last_login_at` 每晚多出一版。代价是：不在 `check_cols` 里的 overwrite 列在版本写入那一刻就**冻结**，未变化的版本永不刷新 —— current dim 必须"版本列从 history 取，overwrite 列从今天的 dump 取"。直接读 snapshot 当前行时，E02 还叫 Ben Okafor、三个 login 是旧值，而 V9 / V10 只比 key 和非空，**全绿**；当前版本恰好在 run 3 写入的 E01 / E07 / E08 碰巧对，半张表替 bug 打了掩护。
- singular test 的语义是"返回任何一行即失败"，所以测试有两种方向相反的写坏法，必须在已知输入上**红一次、绿一次**才能信：V12 `select case when … end as flag` 不加 `where`，对账正确时也返回 flag 为 NULL 的行 → 永远红；V6 先筛出不一致、再 `group by … having count(*) > 1`，每个员工最多一行失败全被吞掉 → 永远绿（6 处真实不一致，`PASS`）。在 `dbt build` 里红错的测试不只是噪音：snapshot 上的 V7 一失败，下游 `int` / dim / agg 连同它们的测试全部 SKIP，真正能抓 T2 的 V10 在 run 2 / 3 一次都没跑。顺带两条写测试的零件：可空列比较用 `is distinct from`（NULL-safe 的 `<>`；`1 <> NULL` 求值为 NULL，被 `where` 丢掉）；半开区间 `[from, to)` 为空的条件是 `to <= from`，零宽也算空，而 overlap 检查看不见它。

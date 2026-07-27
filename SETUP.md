# Setup — migrating the dbt practice system to Claude Code

## 1. Target layout

```
dbt-daily-practice/                 <- open Claude Code here (repo root)
├── CLAUDE.md                       <- project memory, loaded automatically
├── SETUP.md                        <- this file
├── .gitignore
├── profiles.example.yml
├── .claude/
│   └── commands/                   <- names match the PySpark practice repo
│       ├── newday.md
│       ├── genprompt.md
│       ├── review.md
│       ├── digest.md
│       ├── env.md                  <- dbt-only
│       └── lineage.md              <- dbt-only
├── docs/                           <- the authoritative specs (copy yours in)
│   ├── 01_practice_workflow_v1.md
│   ├── 02_problem_format_and_templates.md
│   ├── 03_environment_setup.md
│   ├── 04_curriculum_backlog.md
│   ├── 05_progress_log.md
│   └── 06_key_takeaways.md         <- cumulative, bullets only, git-diffed daily
├── days/                           <- per-day prose artifacts
│   └── day1/
│       ├── STAGE                   <- single line: current stage
│       ├── problem.md
│       ├── notes.md                <- assumptions + debrief answers
│       ├── reference_solution.md   <- pasted back from the incognito session
│       ├── verdict.md              <- MUST be committed before /verify
│       ├── digest.md
│       └── .traps.md               <- written at problem time, not read until Stage 4
├── scripts/
│   └── newday.sh
├── docker-compose.yml              <- from docs/03
├── Dockerfile                      <- from docs/03
├── profiles.yml                    <- gitignored
└── dbt_practice/                   <- the actual dbt project
    ├── dbt_project.yml
    ├── models/day1/{staging,marts}/
    └── seeds/day1/
```

**Why `days/` is separate from `dbt_practice/models/dayN/`:** prose artifacts (problem,
verdict, digest) and executable code have different owners and different read rules.
Claude is forbidden from reading `dbt_practice/models/**` during Stage 1 but must read
`days/dayN/problem.md` freely. Keeping them in separate trees makes that rule mechanical
instead of aspirational.

## 2. First-time setup

```bash
mkdir dbt-daily-practice && cd dbt-daily-practice
git init

# drop in the files from this bundle: CLAUDE.md, SETUP.md, .claude/, .gitignore,
# profiles.example.yml, scripts/newday.sh

mkdir docs days
# copy your five spec files into docs/
# copy Dockerfile, docker-compose.yml, dbt_practice/ from your existing setup

cp profiles.example.yml profiles.yml
docker compose up -d dbt
docker compose exec dbt dbt debug

git add -A && git commit -m "Migrate dbt practice system to Claude Code"
claude
```

Do **not** run `/init` — it would overwrite `CLAUDE.md` with an auto-generated one.

Command names deliberately match `PysparkDailyPractices/.claude/commands/`. Project-scoped
commands are visible only inside their own repo, so `/digest` in this repo and `/digest`
in the PySpark repo never collide — the only thing that matters is which directory you
opened Claude Code in.

## 3. The STAGE file

One line, one of:

```
0-not-started   1-solve   2-generate   3-review   4-verify   5-digest   done
```

This is the single source of truth for what Claude is allowed to do. Claude reads it
and never writes it except at the end of `/verify` and `/digest`. If you get an answer
that feels too helpful for the stage you are in, check this file first — a stale
`0-not-started` is the most likely cause.

## 4. A day, end to end

```
/env                              容器 + dbt debug + dbt parse
/newday NN                        Claude 提议选题 → 你确认 → 生成 problem.md + .traps.md
/clear                            ★ 必须。traps 现在在上下文里
        |
        v
 （自己写 models/dayNN/ 的 staging + marts + schema.yml）
docker compose exec dbt dbt build --select path:models/dayNN
/lineage NN                       结构检查：上游有没有混进别的天
        |                         自己跑，直到 build 绿 + 输出对得上
        v
STAGE -> 2-generate
/genprompt NN                     输出一段 prompt
  -> 复制到 web 端 incognito 对话，拿 AI 解
  -> 原样贴进 reference_solution.md，不要改一个字
        |
        v
 （读参考答案，写 verdict.md —— 实跑之前必须先下结论）
git add days/dayNN/verdict.md && git commit -m "day NN verdict"
        |
        v
/review NN                        Claude 也先盲审 -> 实跑 -> 三方对比 -> 批改你的 verdict
/digest NN                        更新 05 和 06（唯一会写 log 的命令）
        |
        v
git diff docs/06_key_takeaways.md    ★ 十秒钟，只看新增行
git add -A && git commit -m "day NN: <topic>"
```

Same shape as the PySpark repo. The two dbt-only steps are `/env` (there is a container
to be alive or not) and `/lineage` (there is a cross-file DAG that can silently point at
the wrong day).

## 5. What Claude Code changes, and what it doesn't

**Changes:** no more pasting SQL and YAML into chat. Claude reads
`dbt_practice/models/dayN/` directly, runs `dbt build` in the container, and edits
`docs/05_progress_log.md` itself.

**Does not change:** Stage 2 still happens **outside this repo**. An agent that has read
your solution cannot produce an independent reference answer — that is the entire point
of the blind-generation protocol, and file access makes it stricter, not looser. Use
an incognito conversation, as before.

## 6. Guardrails worth knowing about

- **`/clear` right after `/newday` is the real trap protection.** `.traps.md` being
  hidden and CLAUDE.md forbidding it are soft guardrails — ask directly and Claude
  complies. `/clear` is different in kind: it removes the traps from context entirely.
  Do not skip it because the day "feels easy".
- **Git is the enforcement mechanism for verdict-before-verification.** An uncommitted
  verdict can be silently edited after seeing results; a committed one cannot. `/verify`
  checks `git log` before running anything.
- **Never run `dbt` on the host.** All commands go through
  `docker compose exec dbt …`. dbt and DuckDB must share a process space.
- Consider `git commit` at the end of each stage. The commit history becomes a second
  record of the workflow, and makes "did I really write the verdict first?" auditable.

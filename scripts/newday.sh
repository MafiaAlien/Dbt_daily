#!/usr/bin/env bash
# Scaffold the directories for a new practice day.
# Usage: ./scripts/newday.sh 3 [medium]
set -euo pipefail

D="${1:?usage: newday.sh <day-number> [medium]}"
LEVEL="${2:-easy}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

mkdir -p "$ROOT/dbt_practice/models/day${D}/staging"
mkdir -p "$ROOT/dbt_practice/models/day${D}/marts"
mkdir -p "$ROOT/dbt_practice/seeds/day${D}"
[ "$LEVEL" = "easy" ] || mkdir -p "$ROOT/dbt_practice/models/day${D}/intermediate"

mkdir -p "$ROOT/days/day${D}"
[ -f "$ROOT/days/day${D}/STAGE" ] || echo "0-not-started" > "$ROOT/days/day${D}/STAGE"
[ -f "$ROOT/days/day${D}/notes.md" ] || printf '## Assumptions\n\n## Debrief answers\n' \
  > "$ROOT/days/day${D}/notes.md"

echo "Created day${D} directories."
echo
echo "Paste this into dbt_practice/dbt_project.yml under  models: -> dbt_practice: ..."
echo
cat <<YAML
    day${D}:
      staging:
        +materialized: view
      marts:
        +materialized: table
YAML
echo
echo "Naming reminder: every model and seed needs the _d${D}_ prefix"
echo "  seeds/day${D}/raw_d${D}_<name>.csv"
echo "  models/day${D}/staging/stg_d${D}_<name>.sql"
echo "  models/day${D}/marts/fct_d${D}_<name>.sql"

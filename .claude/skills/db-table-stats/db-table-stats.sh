#!/usr/bin/env bash
set -euo pipefail

# db-table-stats: show estimated row counts per table in the dev Postgres
# Usage:
#   db-table-stats.sh [--limit N] [--exact-top N] [--json]
#   --limit N      : number of tables to show (default 20)
#   --exact-top N  : for the top N tables run COUNT(*) to show exact counts (slower)
#   --json         : emit raw JSON if using an MCP wrapper
#
# Behavior:
# 1) Prefer the project's MCP wrapper (repo .claude/skills or .github/skills petclinic-db-cli wrapper)
# 2) Then try mcptools if present
# 3) Then try a local psql client (brew libpq)
# 4) If none available, offer to install libpq via Homebrew (interactive)

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
LIMIT=20
EXACT_TOP=0
EMIT_JSON=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --limit) LIMIT="$2"; shift 2 ;;
    --exact-top) EXACT_TOP="$2"; shift 2 ;;
    --json) EMIT_JSON=1; shift ;;
    -h|--help) sed -n '1,120p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "Unknown arg: $1"; exit 2 ;;
  esac
done

SQL='SELECT relname AS table_name, n_live_tup AS row_estimate FROM pg_stat_user_tables ORDER BY n_live_tup DESC LIMIT '"$LIMIT"";"

print_table() {
  # arguments: table row
  printf "%-30s %10s\n" "$1" "$2"
}

# Try the MCP wrapper(s)
WRAPPER1="$ROOT_DIR/.claude/skills/petclinic-db-cli/db-via-mcp.sh"
WRAPPER2="$ROOT_DIR/.github/skills/petclinic-db-cli/db-via-mcp.sh"

if [[ -x "$WRAPPER1" ]]; then
  if [[ "$EMIT_JSON" -eq 1 ]]; then
    "$WRAPPER1" call execute_sql --params "{\"sql\":\"$SQL\"}"
    exit 0
  fi
  echo "Using MCP wrapper: $WRAPPER1"
  "$WRAPPER1" call execute_sql --params "{\"sql\":\"$SQL\"}" | \
    jq -r '.data.statements[0].rows[] | [.0, .1] | @tsv' 2>/dev/null || \
    python3 -c 'import sys,json; r=json.load(sys.stdin); print("\n".join(["\t".join(map(str,x)) for x in r["data"]["statements"][0]["rows"]]))'
  exit 0
fi

if [[ -x "$WRAPPER2" ]]; then
  if [[ "$EMIT_JSON" -eq 1 ]]; then
    "$WRAPPER2" call execute_sql --params "{\"sql\":\"$SQL\"}"
    exit 0
  fi
  echo "Using MCP wrapper: $WRAPPER2"
  "$WRAPPER2" call execute_sql --params "{\"sql\":\"$SQL\"}" | \
    jq -r '.data.statements[0].rows[] | [.0, .1] | @tsv' 2>/dev/null || \
    python3 -c 'import sys,json; r=json.load(sys.stdin); print("\n".join(["\t".join(map(str,x)) for x in r["data"]["statements"][0]["rows"]]))'
  exit 0
fi

# Try mcptools
if command -v mcptools >/dev/null 2>&1; then
  echo "Using mcptools to call the DB server"
  mcptools call execute_sql --params "{\"sql\":\"$SQL\"}" | jq -r '.data.statements[0].rows[] | [.0, .1] | @tsv'
  exit 0
fi

# Try psql
PSQL_CMD=""
if command -v psql >/dev/null 2>&1; then
  PSQL_CMD="psql"
else
  if command -v brew >/dev/null 2>&1; then
    echo "psql not found. libpq (psql) can be installed via Homebrew."
    read -p "Install libpq via Homebrew now? [y/N] " yn
    case "$yn" in
      [Yy]*)
        brew install libpq
        BREW_PREFIX=$(brew --prefix libpq)
        PSQL_CMD="$BREW_PREFIX/bin/psql"
        ;;
      *)
        echo "Aborting: psql not available and installation declined."; exit 2
        ;;
    esac
  else
    echo "psql not found and Homebrew not available. Please install psql or use the project's MCP wrapper." >&2
    exit 2
  fi
fi

if [[ -n "$PSQL_CMD" ]]; then
  echo "Using psql: $PSQL_CMD"
  # Use the default embedded DB credentials used by the project's starter
  export PGPASSWORD="petclinic"
  # Attempt connection with known defaults
  # First try to run the estimated rows query
  set +e
  OUT=$($PSQL_CMD -U petclinic -h localhost -p 5432 -d petclinic -Atc "$SQL" 2>/dev/null)
  RC=$?
  set -e
  if [[ $RC -ne 0 ]]; then
    echo "psql failed to connect with default credentials. Either start the embedded DB or provide access. Exiting." >&2
    exit $RC
  fi

  # Print header
  printf "%-30s %10s\n" "table" "rows_est"
  printf "%-30s %10s\n" "------------------------------" "----------"
  echo "$OUT" | awk -F'|' '{printf "%-30s %10s\n", $1, $2}'

  if [[ $EXACT_TOP -gt 0 ]]; then
    echo
    echo "Computing exact COUNT(*) for top $EXACT_TOP tables (this may be slow)"
    # get top N table names
    TOP_TABLES=$($PSQL_CMD -U petclinic -h localhost -p 5432 -d petclinic -Atc "SELECT relname FROM pg_stat_user_tables ORDER BY n_live_tup DESC LIMIT $EXACT_TOP;")
    printf "%-30s %10s\n" "table" "rows_exact"
    printf "%-30s %10s\n" "------------------------------" "----------"
    while IFS= read -r t; do
      # protect identifiers by double-quoting
      CNT=$($PSQL_CMD -U petclinic -h localhost -p 5432 -d petclinic -Atc "SELECT count(*) FROM \"$t\";")
      printf "%-30s %10s\n" "$t" "$CNT"
    done <<< "$TOP_TABLES"
  fi
  exit 0
fi

# Fallback - shouldn't reach here
echo "No DB access method available." >&2
exit 2

db-table-stats skill

This skill/script helps inspect which tables have the most rows in the local dev Postgres used by this project.

Features:
- Prefer the project's MCP wrapper if available (safe, no DB creds in plaintext)
- Fallback to mcptools if present
- Then try local psql (Homebrew libpq) and optionally install it interactively
- Optional --exact-top N to run COUNT(*) on top N tables (slow)

Usage examples:

# show top 20 estimated rows
.github/skills/db-table-stats/db-table-stats.sh

# show top 10
.github/skills/db-table-stats/db-table-stats.sh --limit 10

# run exact COUNT(*) on the top 3 tables (slower)
.github/skills/db-table-stats/db-table-stats.sh --exact-top 3

# If the project ships an MCP wrapper (.claude/skills or .github/skills petclinic-db-cli), it will use it automatically.

Notes:
- The script assumes the embedded DB credentials used by the project: user=petclinic, password=petclinic, db=petclinic, host=localhost, port=5432.
- The script is read-only by default.
- Contributions/improvements welcome: add non-interactive install flags, support for custom DSNs, or output formats (CSV/JSON).

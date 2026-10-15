#!/usr/bin/env bash
# Launches the REA MCP server over stdio with a Node.js version REA supports.
#
# REA needs Node 22.x >= 22.19, 24.x >= 24.11, or 26+; its
# inspect_sqlite_database tool additionally needs 24.x >= 24.15 or 26+.
# Claude Code's cloud image only puts Node 22 on PATH, and it starts this
# launcher at the same time as the SessionStart hook, so the launcher cannot
# count on the hook having installed anything yet. When no Node on PATH, under
# ~/.local/node or under /opt serves SQLite inspection, it runs
# scripts/session-start.sh --ensure-node, which installs the latest Node 24
# under ~/.local/node (sharing a lock with the hook), and falls back to any
# supported Node if that fails. Everything printed here goes to stderr: stdout
# is the MCP stream.
set -euo pipefail

REA_PACKAGE="${REA_PACKAGE:-rea-agents@6.5.0}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Same rules as scripts/session-start.sh.
node_ok() {
  local v major minor
  v="$("$1" -v 2>/dev/null)" || return 1
  v="${v#v}"
  major="${v%%.*}"
  minor="${v#*.}"
  minor="${minor%%.*}"
  case "$major" in
    22) [ "$minor" -ge 19 ] ;;
    24) [ "$minor" -ge 11 ] ;;
    26|27|28|29|[3-9][0-9]) true ;;
    *) false ;;
  esac
}

node_sqlite_ok() {
  local v major minor
  v="$("$1" -v 2>/dev/null)" || return 1
  v="${v#v}"
  major="${v%%.*}"
  minor="${v#*.}"
  minor="${minor%%.*}"
  case "$major" in
    24) [ "$minor" -ge 15 ] ;;
    26|27|28|29|[3-9][0-9]) true ;;
    *) false ;;
  esac
}

# Puts a Node accepted by check $1 on PATH: the one already on PATH, else
# ~/.local/node, else the image's /opt builds.
find_node() {
  local dir
  "$1" "$(command -v node || echo /nonexistent)" && return 0
  for dir in "$HOME/.local/node/bin" /opt/node26/bin /opt/node24/bin /opt/node22/bin; do
    if [ -x "$dir/node" ] && "$1" "$dir/node"; then
      export PATH="$dir:$PATH"
      return 0
    fi
  done
  return 1
}

if ! find_node node_sqlite_ok; then
  bash "$here/session-start.sh" --ensure-node >&2 || true
  find_node node_sqlite_ok || find_node node_ok || true
fi

exec npx -y "$REA_PACKAGE" mcp "$@"

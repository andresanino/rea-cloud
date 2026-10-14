#!/usr/bin/env bash
# Launches the REA MCP server over stdio with a Node.js version REA supports.
#
# REA needs Node 22.x >= 22.19, 24.x >= 24.11, or 26+. Claude Code's cloud image
# puts its Node 22 on PATH; if that one is too old, scripts/session-start.sh
# installs a newer Node under ~/.local/node and this launcher picks it up.
set -euo pipefail

REA_PACKAGE="${REA_PACKAGE:-rea-agents@6.5.0}"

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

if ! node_ok "$(command -v node || echo /nonexistent)"; then
  for dir in "$HOME/.local/node/bin" /opt/node26/bin /opt/node24/bin /opt/node22/bin; do
    if [ -x "$dir/node" ] && node_ok "$dir/node"; then
      export PATH="$dir:$PATH"
      break
    fi
  done
fi

exec npx -y "$REA_PACKAGE" mcp "$@"

#!/usr/bin/env bash
# Launches the REA MCP server over stdio with a Node.js version REA supports.
#
# REA needs Node 22.x >= 22.19, 24.x >= 24.11, or 26+; its SQLite inspection
# needs 24.15+. Claude Code's cloud image puts its Node 22 on PATH. A newer
# Node installed by scripts/cloud-setup.sh (/opt/node24) or by
# scripts/session-start.sh (~/.local/node) is preferred when it is at least
# REA_NODE_MAJOR (default 24).
set -euo pipefail

REA_PACKAGE="${REA_PACKAGE:-rea-agents@6.5.0}"
REA_NODE_MAJOR="${REA_NODE_MAJOR:-24}"

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

node_major() { # node-path -> major version
  local v
  v="$("$1" -v 2>/dev/null)" || return 1
  v="${v#v}"
  printf '%s\n' "${v%%.*}"
}

# Same selection as scripts/session-start.sh: the first supported Node that is
# at least REA_NODE_MAJOR, looking at PATH and then the known install
# directories; failing that, the first supported Node at all.
find_node() {
  local pass cand dir
  for pass in preferred any; do
    for cand in "$(command -v node || echo /nonexistent)" "$HOME/.local/node/bin/node" \
                /opt/node26/bin/node /opt/node24/bin/node /opt/node22/bin/node; do
      if [ ! -x "$cand" ] || ! node_ok "$cand"; then continue; fi
      if [ "$pass" = preferred ] && [ "$(node_major "$cand")" -lt "$REA_NODE_MAJOR" ]; then continue; fi
      dir="$(dirname "$cand")"
      case ":$PATH:" in *":$dir:"*) ;; *) export PATH="$dir:$PATH" ;; esac
      return 0
    done
  done
  return 1
}

find_node || true

exec npx -y "$REA_PACKAGE" mcp "$@"

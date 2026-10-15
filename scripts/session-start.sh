#!/usr/bin/env bash
# Prepares a Claude Code cloud session (or any Linux/macOS machine) to run REA.
#
# Used three ways:
#   1. As the SessionStart hook in .claude/settings.json (runs on every session).
#   2. Pasted into a cloud environment's "Setup script" field, so the Node.js
#      and npx cache it produces are kept in the environment cache across
#      sessions instead of being rebuilt each time.
#   3. As `session-start.sh --ensure-node` from scripts/rea-mcp.sh: only picks
#      or installs Node.js and logs to stderr. Claude Code starts the MCP server
#      and this hook at the same time, so the launcher cannot wait for the hook;
#      both share the ~/.local/node.installing lock instead.
#
# Node.js: REA runs on 22.19+, 24.11+ or 26+, but inspect_sqlite_database needs
# 24.15+ or 26+ (native DatabaseSync.limits). The cloud image ships only Node
# 22, so when no Node satisfies SQLite inspection the latest Node
# ${REA_NODE_MAJOR}.x (default 24) is installed under ~/.local/node.
#
# It never exits non-zero: a failed warm-up must not stop the session.
set -uo pipefail

REA_PACKAGE="${REA_PACKAGE:-rea-agents@6.5.0}"
REA_NODE_MAJOR="${REA_NODE_MAJOR:-24}"
NODE_HOME="$HOME/.local/node"
NODE_LOCK="$HOME/.local/node.installing"

log() { printf '[rea-cloud] %s\n' "$*"; }

# REA itself runs on Node 22.19+, 24.11+ or 26+.
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

# inspect_sqlite_database also needs Node 24.15+ or 26+ (DatabaseSync.limits).
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

# Whether the latest release of a major line can serve SQLite inspection.
major_sqlite_ok() {
  case "$1" in
    24|26|27|28|29|[3-9][0-9]) true ;;
    *) false ;;
  esac
}

# Puts a Node accepted by check $1 (node_ok or node_sqlite_ok) on PATH: the one
# already on PATH, else ~/.local/node, else the image's /opt builds.
find_node() {
  local dir
  "$1" "$(command -v node || echo /nonexistent)" && return 0
  for dir in "$NODE_HOME/bin" /opt/node26/bin /opt/node24/bin /opt/node22/bin; do
    if [ -x "$dir/node" ] && "$1" "$dir/node"; then
      export PATH="$dir:$PATH"
      return 0
    fi
  done
  return 1
}

sha256_check() { # expected-hex file
  local actual
  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$2" | awk '{print $1}')"
  else
    actual="$(shasum -a 256 "$2" | awk '{print $1}')"
  fi
  [ "$actual" = "$1" ]
}

# mkdir lock so a session-start.sh and a rea-mcp.sh started together do not
# both download and unpack into ~/.local/node. A lock whose owner is gone is
# removed; waiting is bounded.
lock_node_install() {
  local waited=0 pid
  mkdir -p "$HOME/.local" || return 1
  until mkdir "$NODE_LOCK" 2>/dev/null; do
    pid="$(cat "$NODE_LOCK/pid" 2>/dev/null)"
    case "$pid" in
      '' | *[!0-9]*) ;;
      *) kill -0 "$pid" 2>/dev/null || { rm -rf "$NODE_LOCK"; continue; } ;;
    esac
    [ "$waited" -eq 0 ] && log "waiting for the Node.js install already running (lock $NODE_LOCK)"
    [ "$waited" -ge 300 ] && { log "gave up waiting for $NODE_LOCK"; return 1; }
    sleep 1
    waited=$((waited + 1))
  done
  echo "$$" > "$NODE_LOCK/pid"
  trap 'rm -rf "$NODE_LOCK"' EXIT
}

unlock_node_install() {
  rm -rf "$NODE_LOCK"
  trap - EXIT
}

# Downloads the latest Node.js ${REA_NODE_MAJOR}.x for this platform, verifies
# its SHA-256, unpacks it next to ~/.local/node and renames it into place.
download_node() {
  local platform base sums file sum tmp
  case "$(uname -s)-$(uname -m)" in
    Linux-x86_64)  platform=linux-x64 ;;
    Linux-aarch64) platform=linux-arm64 ;;
    Darwin-arm64)  platform=darwin-arm64 ;;
    Darwin-x86_64) platform=darwin-x64 ;;
    *) log "no Node.js download for $(uname -s)-$(uname -m)"; return 1 ;;
  esac
  base="https://nodejs.org/dist/latest-v${REA_NODE_MAJOR}.x"
  log "installing Node.js ${REA_NODE_MAJOR}.x from $base into $NODE_HOME"
  sums="$(curl -fsSL --connect-timeout 15 --max-time 30 "$base/SHASUMS256.txt")" || { log "could not fetch $base/SHASUMS256.txt"; return 1; }
  file="$(printf '%s\n' "$sums" | awk -v p="$platform" '$2 ~ ("-" p "\\.tar\\.gz$") { print $2; exit }')"
  [ -n "$file" ] || { log "no $platform tarball listed at $base"; return 1; }
  sum="$(printf '%s\n' "$sums" | awk -v f="$file" '$2 == f { print $1; exit }')"
  tmp="$(mktemp -d "$HOME/.local/node.tmp.XXXXXX")" || return 1
  curl -fsSL --connect-timeout 15 --max-time 120 -o "$tmp/$file" "$base/$file" || { log "download of $file failed"; rm -rf "$tmp"; return 1; }
  sha256_check "$sum" "$tmp/$file" || { log "checksum mismatch for $file"; rm -rf "$tmp"; return 1; }
  mkdir "$tmp/node" && tar -xzf "$tmp/$file" -C "$tmp/node" --strip-components=1 \
    || { log "could not extract $file"; rm -rf "$tmp"; return 1; }
  rm -rf "$NODE_HOME" && mv "$tmp/node" "$NODE_HOME" \
    || { log "could not replace $NODE_HOME"; rm -rf "$tmp"; return 1; }
  rm -rf "$tmp"
}

# Installs Node under ~/.local/node (unless a concurrent run just did) and puts
# it on PATH; succeeds only when the result passes check $1.
install_node() {
  local check="$1" rc=0
  lock_node_install || return 1
  if ! "$check" "$NODE_HOME/bin/node"; then
    download_node
    rc=$?
  fi
  unlock_node_install
  [ "$rc" -eq 0 ] || return 1
  export PATH="$NODE_HOME/bin:$PATH"
  "$check" "$NODE_HOME/bin/node"
}

# Selects this process's Node: one that also serves inspect_sqlite_database when
# possible, else any REA runs on. Fails only when there is none at all.
ensure_node() {
  find_node node_sqlite_ok && return 0
  if ! find_node node_ok; then
    install_node node_ok && return 0
  elif major_sqlite_ok "$REA_NODE_MAJOR"; then
    install_node node_sqlite_ok && return 0
  fi
  find_node node_ok
}

report_node() {
  if node_sqlite_ok "$(command -v node)"; then
    log "node $(node -v) at $(command -v node) (SQLite inspection available)"
  else
    log "node $(node -v) at $(command -v node); inspect_sqlite_database unavailable: needs Node 24.15+ or 26+"
  fi
}

main() {
  local ver
  if ensure_node; then
    report_node
  else
    log "WARNING: no supported Node.js (22.19+, 24.11+, or 26+); the rea MCP server cannot start"
    return 0
  fi

  log "warming $REA_PACKAGE in the npx cache"
  if ver="$(npx -y "$REA_PACKAGE" --version 2>/dev/null)"; then
    log "rea-agents $ver ready"
  else
    log "WARNING: npx could not run $REA_PACKAGE (registry unreachable?)"
    return 0
  fi

  if npx -y "$REA_PACKAGE" mcp doctor >/dev/null 2>&1; then
    log "REA MCP server starts and lists its tools"
  else
    log "WARNING: 'rea mcp doctor' failed; run: npx -y $REA_PACKAGE mcp doctor"
  fi

  # Optional analysis engines: report them, never install them.
  if [ -n "${GHIDRA_INSTALL_DIR:-}" ]; then
    log "GHIDRA_INSTALL_DIR=$GHIDRA_INSTALL_DIR"
  elif node_sqlite_ok "$(command -v node)"; then
    log "GHIDRA_INSTALL_DIR not set: no native decompilation; static JS/.NET/archive/APK/Go/Rust/PE/ELF/SQLite/WASM inspection still works"
  else
    log "GHIDRA_INSTALL_DIR not set: no native decompilation; static JS/.NET/archive/APK/Go/Rust/PE/ELF/WASM inspection still works (SQLite needs Node 24.15+ or 26+)"
  fi
}

case "${1:-}" in
  --ensure-node)
    # Called by scripts/rea-mcp.sh; its stdout is the MCP stream, so log to stderr.
    log() { printf '[rea-cloud] %s\n' "$*" >&2; }
    if ensure_node; then
      report_node
    else
      log "WARNING: no supported Node.js (22.19+, 24.11+, or 26+); the rea MCP server cannot start"
    fi
    ;;
  *)
    main
    ;;
esac
exit 0

#!/usr/bin/env bash
# Prepares a Claude Code cloud session (or any Linux/macOS machine) to run REA.
#
# Used two ways:
#   1. As the SessionStart hook in .claude/settings.json (runs on every session).
#   2. Pasted into a cloud environment's "Setup script" field, so the Node.js
#      and npx cache it produces are kept in the environment cache across
#      sessions instead of being rebuilt each time.
#
# It never exits non-zero: a failed warm-up must not stop the session.
set -uo pipefail

REA_PACKAGE="${REA_PACKAGE:-rea-agents@6.5.0}"
REA_NODE_MAJOR="${REA_NODE_MAJOR:-24}"

log() { printf '[rea-cloud] %s\n' "$*"; }

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

find_node() {
  node_ok "$(command -v node || echo /nonexistent)" && return 0
  local dir
  for dir in "$HOME/.local/node/bin" /opt/node26/bin /opt/node24/bin /opt/node22/bin; do
    if [ -x "$dir/node" ] && node_ok "$dir/node"; then
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

install_node() {
  local platform base sums file sum tmp
  case "$(uname -s)-$(uname -m)" in
    Linux-x86_64)  platform=linux-x64 ;;
    Linux-aarch64) platform=linux-arm64 ;;
    Darwin-arm64)  platform=darwin-arm64 ;;
    Darwin-x86_64) platform=darwin-x64 ;;
    *) log "no Node.js download for $(uname -s)-$(uname -m)"; return 1 ;;
  esac
  base="https://nodejs.org/dist/latest-v${REA_NODE_MAJOR}.x"
  log "installing Node.js ${REA_NODE_MAJOR}.x from $base into ~/.local/node"
  sums="$(curl -fsSL "$base/SHASUMS256.txt")" || { log "could not fetch $base/SHASUMS256.txt"; return 1; }
  file="$(printf '%s\n' "$sums" | awk -v p="$platform" '$2 ~ ("-" p "\\.tar\\.gz$") { print $2; exit }')"
  [ -n "$file" ] || { log "no $platform tarball listed at $base"; return 1; }
  sum="$(printf '%s\n' "$sums" | awk -v f="$file" '$2 == f { print $1; exit }')"
  tmp="$(mktemp -d)" || return 1
  curl -fsSL -o "$tmp/$file" "$base/$file" || { log "download of $file failed"; rm -rf "$tmp"; return 1; }
  sha256_check "$sum" "$tmp/$file" || { log "checksum mismatch for $file"; rm -rf "$tmp"; return 1; }
  mkdir -p "$HOME/.local/node" \
    && tar -xzf "$tmp/$file" -C "$HOME/.local/node" --strip-components=1 \
    || { log "could not extract $file"; rm -rf "$tmp"; return 1; }
  rm -rf "$tmp"
  export PATH="$HOME/.local/node/bin:$PATH"
  node_ok "$HOME/.local/node/bin/node"
}

main() {
  local ver
  if find_node || install_node; then
    log "node $(node -v) at $(command -v node)"
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
  else
    log "GHIDRA_INSTALL_DIR not set: no native decompilation; static JS/.NET/archive/APK/Go/Rust/PE/ELF/SQLite/WASM inspection still works"
  fi
}

main
exit 0

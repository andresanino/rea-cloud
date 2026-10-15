#!/usr/bin/env bash
# Sets up a Claude Code cloud environment so REA can run its native and ELF
# tools: Ghidra 12.1.x, a Python with pwntools, and Node.js 24.
#
# Paste this whole file into the cloud environment's "Setup script" field
# (claude.ai/code -> environment settings), add the three environment variables
# it prints at the end, and start a new session. The environment cache keeps
# the installs between sessions as long as the script finishes in about five
# minutes, which is why the three installs run in parallel.
#
#   /opt/ghidra        Ghidra 12.1.x (runs on the image's OpenJDK 21) ->
#                      binary_overview, pseudocode, function analysis
#                      [GHIDRA_INSTALL_DIR]
#   /opt/rea-pwntools  Python venv with pwntools 4.15.0, pyelftools 0.33 and
#                      unicorn 2.1.2 -> inspect_binary_layout
#                      [REA_PWNTOOLS_PYTHON]
#   /opt/node24        Node.js 24.x; REA's SQLite inspection needs 24.15+ ->
#                      inspect_sqlite_database. scripts/rea-mcp.sh and
#                      scripts/session-start.sh prefer it over the image's
#                      Node 22 [REA_NODE_MAJOR]
#
# Each step skips itself when its result is already there, so re-running is
# cheap. The script never exits non-zero: a failed step is logged and the
# others are still cached. It works on any Linux x86-64/arm64 machine that can
# write /opt; set REA_GHIDRA_DIR, REA_PWNTOOLS_VENV and REA_NODE_DIR to test it
# somewhere else. It needs curl, tar, python3 and (for Ghidra) unzip, bsdtar or
# python3's zipfile.
set -uo pipefail

REA_PACKAGE="${REA_PACKAGE:-rea-agents@6.5.0}"

# Ghidra: the newest 12.1.x release on github.com/NationalSecurityAgency/ghidra,
# verified against the SHA-256 published with the release. The pinned release
# is used when the GitHub API cannot be queried. REA_GHIDRA_URL (+
# REA_GHIDRA_SHA256) forces a specific official zip instead.
REA_GHIDRA_DIR="${REA_GHIDRA_DIR:-/opt/ghidra}"
GHIDRA_SERIES="12.1"
GHIDRA_REPO="NationalSecurityAgency/ghidra"
GHIDRA_PINNED_TAG="Ghidra_12.1.4_build"
GHIDRA_PINNED_FILE="ghidra_12.1.4_PUBLIC_20260921.zip"
GHIDRA_PINNED_SHA256="ddac49f903da9d5bac833e5cc79395098b9c33cfd3279be5f31bd00387d2d4db"

# pwntools venv: exactly the versions rea-agents 6.5.0 asks for.
REA_PWNTOOLS_VENV="${REA_PWNTOOLS_VENV:-/opt/rea-pwntools}"
PWNTOOLS_VERSION="4.15.0"
PYELFTOOLS_VERSION="0.33"
UNICORN_VERSION="2.1.2"

# Node.js: the same download-and-checksum logic as scripts/session-start.sh,
# installed into /opt/node<major> so the environment cache keeps it.
REA_NODE_MAJOR="${REA_NODE_MAJOR:-24}"
REA_NODE_DIR="${REA_NODE_DIR:-/opt/node${REA_NODE_MAJOR}}"

# A download (retries included) is cut off after this many seconds so a slow
# mirror cannot push the whole script past the cache budget; the other
# installs still count.
DOWNLOAD_TIMEOUT="${REA_SETUP_DOWNLOAD_TIMEOUT:-270}"

WORK=""

log() { printf '[rea-cloud-setup] %s\n' "$*"; }

fetch() { # url [curl options...]
  curl -fsSL --retry 3 --retry-delay 2 --retry-max-time "$DOWNLOAD_TIMEOUT" \
    --max-time "$DOWNLOAD_TIMEOUT" "$@"
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

can_install_into() { # step dir
  local parent
  parent="$(dirname "$2")"
  if mkdir -p "$parent" 2>/dev/null && [ -w "$parent" ]; then
    return 0
  fi
  log "$1: cannot write $parent (run as root, or set REA_GHIDRA_DIR/REA_PWNTOOLS_VENV/REA_NODE_DIR); skipping"
  return 1
}

# ---------------------------------------------------------------- Ghidra ----

# Reads the GitHub releases listing and prints, for the newest Ghidra
# <series>.x release: tag, zip name, zip URL and the SHA-256 from the release
# notes (empty when none is published), tab-separated.
GHIDRA_PICK_PY=$(cat <<'PY'
import json, re, sys
series, path = sys.argv[1], sys.argv[2]
pattern = re.compile(r'^Ghidra_' + re.escape(series) + r'(?:\.(\d+))?_build$')
best = None
with open(path, encoding='utf-8') as fh:
    releases = json.load(fh)
for rel in releases:
    if rel.get('draft') or rel.get('prerelease'):
        continue
    match = pattern.match(rel.get('tag_name') or '')
    if not match:
        continue
    zips = [a for a in rel.get('assets') or [] if (a.get('name') or '').endswith('.zip')]
    if not zips:
        continue
    patch = int(match.group(1) or 0)
    shas = re.findall(r'\b[0-9a-fA-F]{64}\b', rel.get('body') or '')
    if best is None or patch > best[0]:
        best = (patch, rel['tag_name'], zips[0]['name'], zips[0]['browser_download_url'],
                shas[0].lower() if shas else '')
if best:
    print('\t'.join(best[1:]))
PY
)

# zipfile-based fallback for images without unzip; restores the file modes
# stored in the archive (ghidraRun, analyzeHeadless, the native decompiler).
UNZIP_PY=$(cat <<'PY'
import os, sys, zipfile
src, dst = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(src) as zf:
    for info in zf.infolist():
        path = zf.extract(info, dst)
        mode = (info.external_attr >> 16) & 0o7777
        if mode and not info.is_dir():
            os.chmod(path, mode)
PY
)

ghidra_release() { # prints: tag<TAB>file<TAB>url<TAB>sha256
  local listing="$WORK/ghidra-releases.json"
  command -v python3 >/dev/null 2>&1 || return 1
  fetch "https://api.github.com/repos/$GHIDRA_REPO/releases?per_page=40" \
    -H 'Accept: application/vnd.github+json' -o "$listing" || return 1
  python3 -I -c "$GHIDRA_PICK_PY" "$GHIDRA_SERIES" "$listing"
}

ghidra_version() {
  sed -n 's/^application\.version=//p' "$REA_GHIDRA_DIR/Ghidra/application.properties" 2>/dev/null | head -n 1
}

extract_zip() { # zip dest-dir
  mkdir -p "$2" || return 1
  if command -v unzip >/dev/null 2>&1; then
    unzip -q "$1" -d "$2"
  elif command -v bsdtar >/dev/null 2>&1; then
    bsdtar -xf "$1" -C "$2"
  else
    python3 -I -c "$UNZIP_PY" "$1" "$2"
  fi
}

install_ghidra() {
  local tag='' file='' url='' sha='' zip top
  if [ -x "$REA_GHIDRA_DIR/support/analyzeHeadless" ]; then
    log "ghidra: already installed: Ghidra $(ghidra_version) at $REA_GHIDRA_DIR"
    return 0
  fi
  if [ -e "$REA_GHIDRA_DIR" ] && [ ! -d "$REA_GHIDRA_DIR/Ghidra" ] && [ -n "$(ls -A "$REA_GHIDRA_DIR" 2>/dev/null)" ]; then
    log "ghidra: $REA_GHIDRA_DIR exists and is not a Ghidra install; not touching it"
    return 1
  fi
  can_install_into ghidra "$REA_GHIDRA_DIR" || return 1
  if ! command -v javac >/dev/null 2>&1 && [ ! -x "${JAVA_HOME:-/nonexistent}/bin/javac" ]; then
    log "ghidra: WARNING: no JDK found (Ghidra 12 needs a JDK 21, a JRE is not enough); installing anyway"
  fi

  if [ -n "${REA_GHIDRA_URL:-}" ]; then
    tag="REA_GHIDRA_URL"; url="$REA_GHIDRA_URL"; file="${url##*/}"; sha="${REA_GHIDRA_SHA256:-}"
    log "ghidra: using $url"
  elif IFS=$'\t' read -r tag file url sha < <(ghidra_release) && [ -n "$url" ]; then
    log "ghidra: newest $GHIDRA_SERIES.x release on GitHub is $tag"
  else
    tag="$GHIDRA_PINNED_TAG"; file="$GHIDRA_PINNED_FILE"
    url="https://github.com/$GHIDRA_REPO/releases/download/$tag/$file"
    sha="$GHIDRA_PINNED_SHA256"
    log "ghidra: could not query the GitHub releases API; using the pinned $tag"
  fi
  case "$url" in
    https://github.com/"$GHIDRA_REPO"/releases/download/*) ;;
    *) log "ghidra: refusing to download from $url (not an official release asset)"; return 1 ;;
  esac

  zip="$WORK/$file"
  log "ghidra: downloading $file (about 570 MB)"
  if ! fetch "$url" -o "$zip"; then
    log "ghidra: download failed or took longer than ${DOWNLOAD_TIMEOUT}s; the environment must allow github.com and release-assets.githubusercontent.com"
    return 1
  fi
  if [ -n "$sha" ]; then
    if sha256_check "$sha" "$zip"; then
      log "ghidra: SHA-256 matches the value published with $tag"
    else
      log "ghidra: SHA-256 of $file does not match the published value; not installing"
      return 1
    fi
  else
    log "ghidra: WARNING: no SHA-256 published for $tag; installing unverified"
  fi

  log "ghidra: extracting $file"
  rm -rf "$WORK/ghidra"
  extract_zip "$zip" "$WORK/ghidra" || { log "ghidra: could not extract $file"; return 1; }
  rm -f "$zip"
  top="$(find "$WORK/ghidra" -maxdepth 2 -name ghidraRun -print 2>/dev/null | head -n 1)"
  [ -n "$top" ] || { log "ghidra: ghidraRun not found in $file"; return 1; }
  top="$(dirname "$top")"
  chmod +x "$top/ghidraRun" "$top/support/analyzeHeadless" "$top"/support/*.sh 2>/dev/null || true
  find "$top" -path '*/os/*' -type f -exec chmod +x {} + 2>/dev/null || true
  rm -rf "$REA_GHIDRA_DIR"
  mv "$top" "$REA_GHIDRA_DIR" || { log "ghidra: could not move the install into $REA_GHIDRA_DIR"; return 1; }
  log "ghidra: installed Ghidra $(ghidra_version) at $REA_GHIDRA_DIR"
}

# -------------------------------------------------------------- pwntools ----

PWNTOOLS_CHECK_PY=$(cat <<'PY'
import sys
from importlib.metadata import PackageNotFoundError, version
wanted = dict(zip(('pwntools', 'pyelftools', 'unicorn'), sys.argv[1:4]))
problems = []
for name, want in wanted.items():
    try:
        have = version(name)
    except PackageNotFoundError:
        have = 'missing'
    if have != want:
        problems.append(f'{name} {have} (want {want})')
if problems:
    print(', '.join(problems))
    sys.exit(1)
PY
)

PIP_WHEEL_PY=$(cat <<'PY'
import json, sys
for entry in json.load(sys.stdin)['urls']:
    if entry['filename'].endswith('-py3-none-any.whl'):
        print(entry['url'], entry['digests']['sha256'])
        break
PY
)

pwntools_ok() { # venv-python
  [ -x "$1" ] && "$1" -I -c "$PWNTOOLS_CHECK_PY" "$PWNTOOLS_VERSION" "$PYELFTOOLS_VERSION" "$UNICORN_VERSION" >/dev/null 2>&1
}

# Installs pip into a venv created with --without-pip (images whose python3
# lacks ensurepip), using pip's own wheel from PyPI.
bootstrap_pip() { # venv-python
  local url='' sha='' whl
  read -r url sha < <(fetch https://pypi.org/pypi/pip/json | python3 -I -c "$PIP_WHEEL_PY")
  [ -n "$url" ] && [ -n "$sha" ] || return 1
  whl="$WORK/${url##*/}"
  fetch "$url" -o "$whl" || return 1
  sha256_check "$sha" "$whl" || { log "pwntools: SHA-256 mismatch for ${whl##*/}"; return 1; }
  "$1" "$whl/pip" install --quiet --no-cache-dir --disable-pip-version-check "$whl"
}

install_pwntools() {
  local py="$REA_PWNTOOLS_VENV/bin/python"
  if pwntools_ok "$py"; then
    log "pwntools: already installed: pwntools $PWNTOOLS_VERSION, pyelftools $PYELFTOOLS_VERSION, unicorn $UNICORN_VERSION at $py"
    return 0
  fi
  if [ -e "$REA_PWNTOOLS_VENV" ] && [ ! -f "$REA_PWNTOOLS_VENV/pyvenv.cfg" ]; then
    log "pwntools: $REA_PWNTOOLS_VENV exists and is not a venv; not touching it"
    return 1
  fi
  can_install_into pwntools "$REA_PWNTOOLS_VENV" || return 1
  command -v python3 >/dev/null 2>&1 || { log "pwntools: python3 not found; skipping"; return 1; }

  log "pwntools: creating a venv with $(python3 --version 2>&1) at $REA_PWNTOOLS_VENV"
  rm -rf "$REA_PWNTOOLS_VENV"
  if ! python3 -m venv "$REA_PWNTOOLS_VENV" >/dev/null 2>&1; then
    log "pwntools: python3 -m venv could not bootstrap pip (python3-venv not installed?); creating it without pip and fetching pip from PyPI"
    rm -rf "$REA_PWNTOOLS_VENV"
    python3 -m venv --without-pip "$REA_PWNTOOLS_VENV" || { log "pwntools: could not create the venv"; return 1; }
    bootstrap_pip "$py" || { log "pwntools: could not install pip into the venv"; return 1; }
  fi
  log "pwntools: installing pwntools==$PWNTOOLS_VERSION pyelftools==$PYELFTOOLS_VERSION unicorn==$UNICORN_VERSION"
  if ! "$py" -m pip install --quiet --no-cache-dir --no-input --disable-pip-version-check \
      --only-binary unicorn \
      "pwntools==$PWNTOOLS_VERSION" "pyelftools==$PYELFTOOLS_VERSION" "unicorn==$UNICORN_VERSION"; then
    log "pwntools: pip install failed (pypi.org and files.pythonhosted.org must be reachable)"
    return 1
  fi
  if ! "$py" -I -c "$PWNTOOLS_CHECK_PY" "$PWNTOOLS_VERSION" "$PYELFTOOLS_VERSION" "$UNICORN_VERSION"; then
    log "pwntools: the installed versions do not match the pins"
    return 1
  fi
  log "pwntools: installed pwntools $PWNTOOLS_VERSION, pyelftools $PYELFTOOLS_VERSION, unicorn $UNICORN_VERSION at $py"
}

# --------------------------------------------------------------- Node.js ----

node_major() { # node-path -> major version
  local v
  v="$("$1" -v 2>/dev/null)" || return 1
  v="${v#v}"
  printf '%s\n' "${v%%.*}"
}

install_node() {
  local dir="$REA_NODE_DIR" platform base sums file sum
  if [ -x "$dir/bin/node" ] && [ "$(node_major "$dir/bin/node")" = "$REA_NODE_MAJOR" ]; then
    log "node: already installed: node $("$dir/bin/node" -v) at $dir"
    return 0
  fi
  if [ -e "$dir" ] && [ -n "$(ls -A "$dir" 2>/dev/null)" ]; then
    log "node: $dir exists and does not hold a Node.js $REA_NODE_MAJOR; not touching it"
    return 1
  fi
  can_install_into node "$dir" || return 1
  case "$(uname -s)-$(uname -m)" in
    Linux-x86_64)  platform=linux-x64 ;;
    Linux-aarch64) platform=linux-arm64 ;;
    Darwin-arm64)  platform=darwin-arm64 ;;
    Darwin-x86_64) platform=darwin-x64 ;;
    *) log "node: no Node.js download for $(uname -s)-$(uname -m)"; return 1 ;;
  esac
  base="https://nodejs.org/dist/latest-v${REA_NODE_MAJOR}.x"
  sums="$(fetch "$base/SHASUMS256.txt")" || { log "node: could not fetch $base/SHASUMS256.txt"; return 1; }
  file="$(printf '%s\n' "$sums" | awk -v p="$platform" '$2 ~ ("-" p "\\.tar\\.gz$") { print $2; exit }')"
  [ -n "$file" ] || { log "node: no $platform tarball listed at $base"; return 1; }
  sum="$(printf '%s\n' "$sums" | awk -v f="$file" '$2 == f { print $1; exit }')"
  log "node: downloading $file"
  fetch "$base/$file" -o "$WORK/$file" || { log "node: download of $file failed"; return 1; }
  sha256_check "$sum" "$WORK/$file" || { log "node: checksum mismatch for $file"; return 1; }
  rm -rf "$dir.partial"
  if ! mkdir -p "$dir.partial" || ! tar -xzf "$WORK/$file" -C "$dir.partial" --strip-components=1; then
    log "node: could not extract $file"
    rm -rf "$dir.partial"
    return 1
  fi
  rm -f "$WORK/$file"
  rm -rf "$dir"
  mv "$dir.partial" "$dir" || { log "node: could not move the install into $dir"; return 1; }
  log "node: installed node $("$dir/bin/node" -v) at $dir"
}

# ------------------------------------------------------------------ main ----

# Warms the npx cache like scripts/session-start.sh does, so the Setup script
# field only needs this file.
warm_rea() {
  local ver
  if [ -x "$REA_NODE_DIR/bin/node" ]; then
    export PATH="$REA_NODE_DIR/bin:$PATH"
  fi
  command -v npx >/dev/null 2>&1 || { log "npx not found; skipping the $REA_PACKAGE warm-up"; return 0; }
  log "warming $REA_PACKAGE in the npx cache with node $(node -v 2>/dev/null)"
  if ver="$(npx -y "$REA_PACKAGE" --version 2>/dev/null)"; then
    log "rea-agents $ver ready"
  else
    log "WARNING: npx could not run $REA_PACKAGE (registry.npmjs.org unreachable?)"
  fi
}

outcome() { if [ "$1" -eq 0 ]; then printf 'ok'; else printf 'FAILED'; fi; }

main() {
  local parent pid_ghidra pid_pwntools pid_node st_ghidra st_pwntools st_node jvm
  log "setting up REA engines on $(uname -s) $(uname -m) as $(id -un 2>/dev/null || echo unknown), $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  parent="$(dirname "$REA_GHIDRA_DIR")"
  mkdir -p "$parent" 2>/dev/null || true
  rm -rf "$parent"/rea-cloud-setup.* 2>/dev/null || true
  WORK="$(mktemp -d "$parent/rea-cloud-setup.XXXXXX" 2>/dev/null || mktemp -d)" \
    || { log "cannot create a work directory; nothing installed"; return 0; }

  install_ghidra & pid_ghidra=$!
  install_pwntools & pid_pwntools=$!
  install_node & pid_node=$!
  wait "$pid_ghidra"; st_ghidra=$?
  wait "$pid_pwntools"; st_pwntools=$?
  wait "$pid_node"; st_node=$?
  rm -rf "$WORK"

  warm_rea || true

  log "result: ghidra=$(outcome "$st_ghidra") pwntools=$(outcome "$st_pwntools") node=$(outcome "$st_node")"
  log "Put these lines in the cloud environment's Environment variables field, then start a new session:"
  printf '%s\n' \
    "GHIDRA_INSTALL_DIR=$REA_GHIDRA_DIR" \
    "REA_PWNTOOLS_PYTHON=$REA_PWNTOOLS_VENV/bin/python" \
    "REA_NODE_MAJOR=$REA_NODE_MAJOR"
  if ! command -v java >/dev/null 2>&1; then
    for jvm in /usr/lib/jvm/java-21-openjdk-amd64 /usr/lib/jvm/java-21-openjdk-arm64 /usr/lib/jvm/java-21-openjdk /opt/java/openjdk; do
      if [ -x "$jvm/bin/java" ]; then
        log "java is not on PATH; Ghidra also needs this line:"
        printf 'JAVA_HOME=%s\n' "$jvm"
        break
      fi
    done
  fi
}

main
exit 0

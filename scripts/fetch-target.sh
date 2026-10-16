#!/usr/bin/env bash
# Fetch an artifact into targets/<name>/ and write its NOTES.md, so a Claude
# Code cloud session can analyze it with REA without anything being committed
# beforehand. Pure intake: nothing is executed, parsed or unpacked beyond the
# registry tarball itself.
#
# Usage:
#   scripts/fetch-target.sh <name> <source> [question ...]
#
#   <name>    folder name under targets/ (letters, digits, dot, dash, underscore)
#   <source>  one of
#     npm:<package>[@<version>]          npm registry tarball, via `npm pack`
#     gh:<owner>/<repo>@<tag>/<asset>    GitHub Release asset
#     https://... | http://...           direct download
#     <path>                             file or directory already on disk
#                                        (an uploaded file, another folder)
#   question  free text recorded in NOTES.md; separate several with " | "
#
# Environment:
#   TARGETS_DIR  base directory, default targets/ (relative to the repo root)
#   FORCE=1      add to an existing, non-empty target folder; NOTES.md and
#                SHA256SUMS are regenerated, so pass the questions again
#
# From a cloud session, GitHub Release downloads and the npm registry work;
# other URLs, raw.githubusercontent.com included, are usually blocked (403).
# For anything else attach the file to the session or publish it as a GitHub
# Release asset.
#
# Output: targets/<name>/ with the fetched files, SHA256SUMS (every file) and
# NOTES.md (origin, fetch date, size and SHA-256 per file, the questions). A
# NOTES.md or SHA256SUMS that came with the artifact is kept as
# NOTES.source.md / SHA256SUMS.source.
set -euo pipefail

usage() {
  sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 2
}

log() { printf '[fetch-target] %s\n' "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

digest() { # file -> sha256 hex
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

size_of() { wc -c <"$1" | tr -d ' '; }

[ $# -ge 2 ] || usage
name="$1"; source="$2"; shift 2
question="$*"

case "$name" in
  ''|*/*|.|..) die "name must be a plain folder name, got '$name'" ;;
  *[!A-Za-z0-9._-]*) die "name may only contain letters, digits, '.', '_' and '-', got '$name'" ;;
esac

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
base="${TARGETS_DIR:-targets}"
case "$base" in /*) ;; *) base="$root/$base" ;; esac
dest="$base/$name"

if [ -e "$dest" ] && [ -n "$(ls -A "$dest" 2>/dev/null)" ] && [ "${FORCE:-0}" != "1" ]; then
  die "$dest already exists and is not empty (set FORCE=1 to add to it)"
fi

tmp="$(mktemp -d)"
created=0
cleanup() {
  local rc=$?
  rm -rf "$tmp"
  # A failed fetch must not leave an empty target folder behind.
  if [ "$rc" -ne 0 ] && [ "$created" = 1 ]; then rmdir "$dest" 2>/dev/null || true; fi
}
trap cleanup EXIT
stage="$tmp/stage"
mkdir -p "$stage" "$tmp/dl"

# Every source mode fills $stage; the common tail below moves it into place.
origin=""
case "$source" in
  npm:*)
    spec="${source#npm:}"
    [ -n "$spec" ] || die "npm source needs a package spec, e.g. npm:left-pad@1.3.0"
    command -v npm >/dev/null 2>&1 || die "npm is not on PATH"
    log "npm pack $spec"
    json="$(npm pack "$spec" --pack-destination "$tmp/dl" --json --loglevel=error)" \
      || die "npm pack failed for $spec (unknown package/version, or registry unreachable)"
    read -r filename pkgname version <<<"$(node -e '
      const a = JSON.parse(process.argv[1]); const p = Array.isArray(a) ? a[0] : a;
      console.log(p.filename, p.name, p.version);' "$json")"
    [ -f "$tmp/dl/$filename" ] || die "npm pack did not produce $filename"
    tarball_sha="$(digest "$tmp/dl/$filename")"
    mkdir "$tmp/x"
    tar -xzf "$tmp/dl/$filename" -C "$tmp/x"
    # Registry tarballs normally unpack to package/; tolerate another single root.
    set -- "$tmp/x"/*
    if [ $# -eq 1 ] && [ -d "$1" ]; then pkgroot="$1"; else pkgroot="$tmp/x"; fi
    cp -a "$pkgroot/." "$stage/"
    origin="npm registry, package \`$pkgname@$version\` (requested \`$spec\`), tarball \`$filename\` SHA-256 \`$tarball_sha\`, unpacked"
    ;;
  gh:*)
    spec="${source#gh:}"
    repo="${spec%%@*}"; rest="${spec#*@}"
    tag="${rest%%/*}"; asset="${rest#*/}"
    case "$repo" in */*) ;; *) die "gh source must be gh:<owner>/<repo>@<tag>/<asset>" ;; esac
    { [ "$rest" != "$spec" ] && [ -n "$tag" ] && [ -n "$asset" ] && [ "$asset" != "$rest" ]; } \
      || die "gh source must be gh:<owner>/<repo>@<tag>/<asset>"
    url="https://github.com/$repo/releases/download/$tag/$asset"
    log "downloading release asset $asset from $repo@$tag"
    if command -v gh >/dev/null 2>&1 \
       && gh release download "$tag" --repo "$repo" --pattern "$asset" --dir "$stage" >/dev/null 2>&1; then
      :
    else
      curl -fsSL --retry 3 --retry-delay 2 -o "$stage/$asset" "$url" \
        || die "could not download $url (private release, wrong tag/asset, or host blocked)"
    fi
    origin="GitHub Release asset \`$asset\` of \`$repo\` at tag \`$tag\` (<$url>)"
    ;;
  http://*|https://*)
    url="$source"
    path="${url%%\?*}"; path="${path%%#*}"
    fname="$(basename "$path")"
    case "$fname" in ''|/|.) fname="download" ;; esac
    log "downloading $url"
    curl -fsSL --retry 3 --retry-delay 2 -o "$stage/$fname" "$url" \
      || die "could not download $url (from a cloud session only GitHub Release downloads and package registries work; raw.githubusercontent.com and most other hosts return 403)"
    origin="downloaded from <$url>"
    ;;
  *)
    [ -e "$source" ] || die "no such file or directory: $source"
    src_abs="$(cd "$(dirname "$source")" && pwd)/$(basename "$source")"
    if [ -d "$source" ]; then
      log "copying directory $src_abs"
      cp -a "$source/." "$stage/"
      origin="copied from local directory \`$src_abs\`"
    else
      log "copying file $src_abs"
      cp -a "$source" "$stage/"
      origin="copied from local file \`$src_abs\`"
    fi
    ;;
esac

# The two metadata names belong to this script; keep the artifact's own copies.
[ ! -f "$stage/NOTES.md" ] || mv "$stage/NOTES.md" "$stage/NOTES.source.md"
[ ! -f "$stage/SHA256SUMS" ] || mv "$stage/SHA256SUMS" "$stage/SHA256SUMS.source"

mkdir -p "$dest"; created=1
cp -a "$stage/." "$dest/"

# Manifest of every file in the target (NOTES.md and SHA256SUMS excluded), sorted.
manifest="$tmp/manifest.tsv"
: >"$manifest"
while IFS= read -r -d '' f; do
  rel="${f#"$dest"/}"
  case "$rel" in NOTES.md|SHA256SUMS) continue ;; esac
  printf '%s\t%s\t%s\n' "$rel" "$(size_of "$f")" "$(digest "$f")" >>"$manifest"
done < <(find "$dest" -type f -print0 | LC_ALL=C sort -z)

count="$(wc -l <"$manifest" | tr -d ' ')"
[ "$count" -gt 0 ] || die "nothing was fetched into $dest"
total="$(awk -F'\t' '{ s += $2 } END { print s + 0 }' "$manifest")"
awk -F'\t' '{ printf "%s  %s\n", $3, $1 }' "$manifest" >"$dest/SHA256SUMS"

big="$(awk -F'\t' '$2 > 52428800 { print $1 " (" $2 " bytes)" }' "$manifest")"
[ -z "$big" ] || log "WARNING: over 50 MB, GitHub warns at 50 MB and rejects at 100 MB; see targets/README.md for Git LFS or Releases: $big"

now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
host="$(uname -s) $(uname -m)"
{
  printf '# %s\n\n' "$name"
  printf -- '- **Origin:** %s.\n' "$origin"
  printf -- '- **Fetched:** %s by `scripts/fetch-target.sh` on %s.\n' "$now" "$host"
  printf -- '- **Identity:** %s file(s), %s bytes in total; the complete list is in `SHA256SUMS`.\n' "$count" "$total"
  printf -- '- **Rule:** only the files listed here are analysed, and nothing in this folder is executed.\n\n'
  printf '| File | Bytes | SHA-256 |\n| --- | --- | --- |\n'
  head -n 40 "$manifest" | awk -F'\t' '{ printf "| `%s` | %s | `%s` |\n", $1, $2, $3 }'
  if [ "$count" -gt 40 ]; then printf '| … | | %s more files, see `SHA256SUMS` |\n' "$((count - 40))"; fi
  printf '\n## Questions to answer\n\n'
  if [ -n "$question" ]; then
    printf '%s\n' "$question" | awk 'BEGIN { RS = "[[:space:]]*\\|[[:space:]]*"; n = 0 } NF { n++; gsub(/^[[:space:]]+|[[:space:]]+$/, ""); printf "%d. %s\n", n, $0 }'
  else
    printf '1. (add the questions this target should answer)\n'
  fi
} >"$dest/NOTES.md"

log "wrote $dest: $count file(s), $total bytes, NOTES.md and SHA256SUMS"
printf '%s\n' "$dest"

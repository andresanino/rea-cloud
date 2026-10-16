---
name: re
description: One-command reverse engineering in this repo. Use when the user asks to reverse engineer, analyze, inspect, explain, compare or rebuild a binary, package, JavaScript bundle, Electron app, .NET assembly, APK, firmware image, network capture, WASM module or SQLite file, whether it already sits under targets/ or still has to be fetched (npm package, GitHub Release asset, URL, uploaded file). Runs intake, REA analysis, the report and the pull request end to end.
argument-hint: <source> [question]
---

# /re: reverse engineer one target, end to end

Arguments: `$ARGUMENTS`. The first word is the source; the rest is the
question. Sources:

| Source | Example |
| --- | --- |
| folder already under `targets/` | `targets/mustache-min` |
| npm package | `npm:left-pad@1.3.0` |
| GitHub Release asset | `gh:owner/repo@v1.2.3/app.asar` |
| direct URL | `https://github.com/owner/repo/releases/download/v1/x.apk` |
| file or folder on disk (uploaded, or anywhere in the container) | `/path/to/firmware.bin` |

With no arguments: list the folders under `targets/` that have no
`reports/<name>-*.md` yet and ask which one to analyze, or show the table
above. Do not pick a target on the user's behalf.

Work through the four stages below in order. When a stage cannot be
completed, say exactly what blocked it and still deliver the stages that did
complete; never guess around a gap.

## 1. Intake

1. If the source is a folder under `targets/`, use it as is; its `NOTES.md`
   carries the origin and the questions. Skip to stage 2.
2. Otherwise choose a short lowercase folder name: `<package>-<version>` for
   npm (drop the scope, replace `/` with `-`), the asset's basename without
   extension for releases and URLs, the file's basename for local paths.
3. Run the intake script, quoting the question so it lands in `NOTES.md`:

   ```bash
   bash scripts/fetch-target.sh <name> <source> "<question>"
   ```

   It downloads or copies the artifact into `targets/<name>/`, writes
   `SHA256SUMS` and a `NOTES.md` with origin, fetch date and per-file
   SHA-256, and executes nothing. Several questions can be separated with
   ` | `.
4. If the download fails, say so plainly: from a cloud session only GitHub
   Release downloads and package registries such as npm work;
   raw.githubusercontent.com and most other hosts return 403. Ask the user
   to attach the file to the session or publish it as a GitHub Release
   asset. Do not try other mirrors on your own.
5. Two checks before fetching anything new:
   - This repository is public while its README says so. Everything pushed
     under `targets/` becomes public. If the artifact is confidential or
     proprietary, stop and tell the user to make the repo private first
     (README, "Visibility") or to keep it in the git-ignored
     `targets/private/`.
   - Analyze only software the user is allowed to analyze
     (`targets/README.md`). If the source is plainly someone else's
     proprietary product and nothing in the request indicates authorization,
     ask before fetching.

## 2. Route and analyze

- Read `.claude/skills/reverse-engineer-anything/SKILL.md` once per session if
  it is not already loaded; its routing table says which REA tool fits which
  artifact.
- Prefer the `rea` MCP tools. If they are absent, run
  `bash scripts/session-start.sh`, read its output, and fall back to the CLI:
  `npx -y rea-agents@6.5.0 <command> --json`, which returns the same Evidence
  records.
- First call by artifact type:

  | Artifact | First tool |
  | --- | --- |
  | JavaScript / Electron (ASAR or tree, npm package) | `analyze_javascript_application` with `detail: "summary"`, then `inspect_analysis_view` |
  | ZIP, APK, IPA, MSIX, DMG, nupkg, other archives | `open_binary`, then `inspect_artifact` |
  | APK code, classes, methods | `inspect_android_package` |
  | .NET assembly | `inspect_managed_artifact`, then `inspect_managed_members` |
  | ELF, PE, Mach-O | `open_binary`; layout with `inspect_binary_layout` or `inspect_with_objdump`; `inspect_go_binary`, `inspect_rust_binary`, `inspect_pe_resources` as relevant |
  | Firmware image | `inspect_firmware_regions` (extract only when asked) |
  | pcap, HAR, SAZ | `inspect_packet_capture`, `inspect_pcap_capture`, `inspect_web_network_capture` |
  | WASM, EVM bytecode, SQLite | `inspect_wasm_artifact`, `inspect_evm_interface`, `inspect_sqlite_database` |

- Work summary-first, then drill into the parts the question needs
  (`inspect_analysis_view`, `trace_application_feature`, the function and
  string tools). Do not repeat an identical analysis.
- The cloud image has no Ghidra or IDA unless `GHIDRA_INSTALL_DIR` is set, so
  native pseudocode and function-level analysis of ELF/PE binaries are
  unavailable; deliver headers, sections, symbols, strings and metadata, and
  say what the missing engine would have added. Optional helpers (tshark,
  pwntools Python, Node 24 for SQLite, apktool, jadx) may be missing too; REA
  reports each one as `provider_unavailable`, quote that rather than guess.
- Never execute the target. Runtime observation needs a local machine and
  an explicit request.

## 3. Report

Write `reports/<name>-<YYYY-MM-DD>.md` in the format of
`reports/mustache-min-2026-10-15.md`:

1. A one-paragraph verdict answering the question.
2. **Target** table: file(s), origin, size and SHA-256 (from `NOTES.md`),
   host, Node and REA version, route used (MCP or CLI).
3. **Observations**, each tied to a REA Evidence ID (`ev_…`) or an exact
   location in the artifact. Static analysis never observed execution; do not
   write as if it did.
4. **Inferences**, clearly separated from observations.
5. **Unknowns and limits**: what was not checked, which engines or helpers
   were missing, what would resolve each gap.
6. **Reproduce**: the exact commands run.

If the user asked for a rebuild, add `rebuilds/<name>/` with a readable
reimplementation and a differential test that runs the original artifact and
the rebuild side by side on the same inputs (worked example:
`rebuilds/mustache/`). Report pass and fail counts.

## 4. Deliver

Commit `targets/<name>/`, the report and any rebuild on the session's branch,
push, and open a draft pull request against `main` titled
`Analyze <name>: <short question>`. Then tell the user, in that order: the
headline answer, the pull request link, and what could not be checked and why.

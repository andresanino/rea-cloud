# rea-cloud

Run [REA — Reverse Engineer Anything](https://github.com/morluto/rea) from
Claude Code **cloud sessions**, with nothing installed on your own machine.

Cloning this repo gives a session everything it needs:

| File | What it does |
| --- | --- |
| `.mcp.json` | Registers REA as the `rea` MCP server (via `scripts/rea-mcp.sh`) |
| `.claude/settings.json` | Auto-approves that server, raises the MCP start timeout, runs the SessionStart hook |
| `scripts/session-start.sh` | Picks (or installs) a supported Node.js, warms the `rea-agents` npx cache, checks the server starts |
| `scripts/cloud-setup.sh` | Optional cloud environment Setup script: installs Ghidra 12.1.x, a pwntools Python and Node 24 into the environment cache (see [Enable native analysis in the cloud](#enable-native-analysis-in-the-cloud)) |
| `.claude/skills/reverse-engineer-anything/` | REA's own skill: how to route targets and report evidence |
| `CLAUDE.md` | Working rules for Claude in this repo |
| `targets/`, `reports/` | Where artifacts go in and findings come out |
| `.devcontainer/` | Same setup for GitHub Codespaces |

## Start a session

1. Put the thing to analyze under `targets/<name>/` and commit it (see
   [targets/README.md](targets/README.md) for large files).
2. Start a cloud session on this repo from any of:
   - **Browser**: [claude.ai/code](https://claude.ai/code) → New session → pick `rea-cloud`
   - **Desktop app**: New session → select **Cloud** → pick `rea-cloud`
   - **Terminal**, from a clone: `claude --cloud "Explain how targets/<name> stores its license key"`
3. Ask the question. The REA tools are loaded automatically; the SessionStart
   hook prints `[rea-cloud] …` lines showing Node, REA version and engine status.

> **Visibility:** this repo is currently *public* so that Claude cloud sessions can clone it
> through a browser-connected GitHub account that has no Claude GitHub App installed on
> `andresanino`. Before committing anything confidential to `targets/`, make it private
> again (`gh repo edit andresanino/rea-cloud --visibility private`) **and** install the
> Claude GitHub App on the `andresanino` account with this repo selected
> (<https://github.com/apps/claude/installations/new>), otherwise cloud sessions lose access.

The repo needs to be visible to your Claude GitHub connection: if the Claude
GitHub App is installed for "selected repositories", add `rea-cloud` at
<https://github.com/apps/claude>.

## What works in the cloud

Without any extra engine REA can statically inspect: JavaScript/Electron apps
(ASAR or extracted), .NET assemblies, archives and packages (ZIP/APK/IPA/MSIX/
DMG), Android APK structure, Go and Rust build metadata, PE resources, ELF
layout/symbols/mitigations, SQLite databases, WebAssembly, EVM bytecode, and
recorded network captures (pcap/HAR/SAZ, given tshark).

Native **decompilation** (`binary_overview`, pseudocode and function analysis
need Ghidra or IDA), `inspect_binary_layout` (needs a Python with pwntools) and
`inspect_sqlite_database` (needs Node 24.15+) need an engine the image lacks.
The next section adds all three with one setup script.

## Enable native analysis in the cloud

`scripts/cloud-setup.sh` installs the missing engines into the cloud
environment, where the environment cache keeps them between sessions:

| Install | Enables |
| --- | --- |
| `/opt/ghidra` — Ghidra 12.1.x from the official GitHub release, SHA-256 checked against the value published with the release; runs on the image's OpenJDK 21 | `binary_overview`, pseudocode and function analysis |
| `/opt/rea-pwntools` — Python venv with pwntools 4.15.0, pyelftools 0.33 and unicorn 2.1.2 | `inspect_binary_layout` |
| `/opt/node24` — Node.js 24 from nodejs.org, checksum-verified; `scripts/rea-mcp.sh` and the hook prefer it over the image's Node 22 | `inspect_sqlite_database` (needs Node 24.15+) |

1. Open the cloud environment's settings (claude.ai/code → environment
   settings) and paste the whole of `scripts/cloud-setup.sh` into the
   **Setup script** field. It also warms the `rea-agents` npx cache, so it
   replaces `scripts/session-start.sh` there.
2. In the **Environment variables** field add these three lines (the script
   prints them again at the end of its output):

   ```
   GHIDRA_INSTALL_DIR=/opt/ghidra
   REA_PWNTOOLS_PYTHON=/opt/rea-pwntools/bin/python
   REA_NODE_MAJOR=24
   ```

3. Restart the session (start a new one). The first start runs the script;
   the three installs run in parallel and the 570 MB Ghidra download is the
   long pole, so expect a few minutes. Later sessions reuse the cached `/opt`
   directories: a re-run skips every install that is already there.

The script prints `[rea-cloud-setup] …` lines and always exits 0, so if a tool
still answers `provider_unavailable`, read the setup output for the step that
failed. Network: besides `registry.npmjs.org`, the environment must reach
`github.com` and `release-assets.githubusercontent.com` (Ghidra), `pypi.org`
and `files.pythonhosted.org` (pwntools) and `nodejs.org` (Node).
`api.github.com` is used to find the newest 12.1.x release; when it is blocked
the script falls back to the release pinned inside it. IDA, Hopper and jadx are
not covered.

## Make sessions start faster

The SessionStart hook does its work on every new VM. To cache it, paste a
script into the cloud environment's **Setup script** field (claude.ai/code →
environment settings): `scripts/cloud-setup.sh` if you want the engines above
(it warms the npx cache too), otherwise `scripts/session-start.sh`. Setup
scripts are cached when they finish in about five minutes, so the installs and
the npx warm-up are reused.

## Local use and Codespaces

- **Local Claude Code**: open a clone and the same `.mcp.json`/hook apply
  (Git Bash supplies `bash` on Windows). If REA is already installed for your
  user, the project-scoped server simply takes precedence.
- **GitHub Codespaces**: `.devcontainer/devcontainer.json` installs Node 24,
  OpenJDK 21 and `rea-agents`, then runs the same warm-up.
- **CLI without MCP**: `npx -y rea-agents@6.5.0 analyze-javascript-application <path> --json`

## Updating REA

The version is pinned to `rea-agents@6.5.0` in `scripts/rea-mcp.sh`,
`scripts/session-start.sh`, `.claude/settings.json`, `.devcontainer/`, and
`CLAUDE.md`. Bump it everywhere, then refresh the bundled skill from a machine
with REA installed (`npx -y rea-agents@<ver> setup --client claude_code --yes`
and copy `~/.claude/skills/reverse-engineer-anything/` here).

## Attribution

`.claude/skills/reverse-engineer-anything/` is bundled from the
[rea-agents](https://www.npmjs.com/package/rea-agents) package (MIT License,
© morluto). Only commit software you are allowed to analyze.

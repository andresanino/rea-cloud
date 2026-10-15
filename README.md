# rea-cloud

Run [REA — Reverse Engineer Anything](https://github.com/morluto/rea) from
Claude Code **cloud sessions**, with nothing installed on your own machine.

Cloning this repo gives a session everything it needs:

| File | What it does |
| --- | --- |
| `.mcp.json` | Registers REA as the `rea` MCP server (via `scripts/rea-mcp.sh`) |
| `.claude/settings.json` | Auto-approves that server, raises the MCP start timeout, runs the SessionStart hook |
| `scripts/session-start.sh` | Picks (or installs) a supported Node.js, warms the `rea-agents` npx cache, checks the server starts |
| `.claude/skills/reverse-engineer-anything/` | REA's own skill: how to route targets and report evidence |
| `CLAUDE.md` | Working rules for Claude in this repo |
| `targets/`, `reports/` | Where artifacts go in and findings come out |
| `rebuilds/` | Clean reimplementations rebuilt from the evidence, with differential tests against the original (worked example: `rebuilds/mustache/`, see `reports/mustache-min-2026-10-15.md`) |
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

Native **decompilation** (pseudocode) needs Ghidra or IDA, which the cloud
image does not include. To add Ghidra, give the cloud environment a setup
script that downloads a Ghidra 12.1.x release (the image already has OpenJDK
21) and exports `GHIDRA_INSTALL_DIR`; the environment cache keeps it between
sessions. See REA's docs for the provider details.

## Make sessions start faster

The SessionStart hook does its work on every new VM. To cache it, paste the
contents of `scripts/session-start.sh` into the cloud environment's **Setup
script** field (claude.ai/code → environment settings). Setup scripts are
cached when they finish in about five minutes, so the Node install and npx
warm-up are reused.

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

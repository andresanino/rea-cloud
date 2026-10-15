# rea-cloud

A reverse-engineering workbench for Claude Code cloud sessions. REA ("Reverse
Engineer Anything", npm `rea-agents`) is registered as the `rea` MCP server in
`.mcp.json`; the `reverse-engineer-anything` skill in `.claude/skills/` says how
to route a target to the right tool and how to report evidence. Read that skill
before the first analysis in a session.

## Layout

- `targets/` — artifacts to analyze: native executables/libraries, Electron
  `app.asar` or extracted JS trees, .NET assemblies, APKs, firmware images,
  pcap/HAR/SAZ captures, WASM, SQLite files. One folder per target with a
  `NOTES.md` (origin, version, the questions to answer).
- `reports/` — one Markdown report per investigation,
  `reports/<target>-<YYYY-MM-DD>.md`.
- `rebuilds/<name>/` — clean reimplementations rebuilt from the evidence, each
  with a differential test against the original artifact (worked example:
  `rebuilds/mustache/`).
- `scripts/rea-mcp.sh` — launches the MCP server with a supported Node.js.
- `scripts/session-start.sh` — SessionStart hook: picks/installs Node, warms the
  `rea-agents` npx cache, runs `rea mcp doctor`, reports optional engines.

## Working here

- Use the `rea` MCP tools directly (`open_binary`, `inspect_artifact`,
  `analyze_javascript_application`, `inspect_managed_artifact`,
  `inspect_android_package`, `inspect_binary_layout`, `inspect_go_binary`,
  `inspect_rust_binary`, `inspect_pe_resources`, `inspect_packet_capture`, …).
  Use the server's actual tool list and schemas; don't call unadvertised tools.
- Do not re-run REA setup or diagnostics before every task. If the `rea` tools
  are missing, run `bash scripts/session-start.sh` and read its output. The CLI
  fallback `npx -y rea-agents@6.5.0 <command> --json` works without MCP.
- Native decompilation (pseudocode, function analysis) needs Ghidra or IDA,
  which are not in the cloud image unless `GHIDRA_INSTALL_DIR` is set by the
  environment's setup script. Static inspection of JS/Electron, .NET, archives,
  APK structure, Go/Rust metadata, PE resources, ELF layout, SQLite, WASM and
  packet captures works without an engine. When a question needs an engine
  that isn't available, say so in the report instead of guessing.
- Reports separate observations (cite REA Evidence IDs), inferences, and
  unknowns, and list what was not checked.
- Never execute an analyzed target unless the user explicitly asks for runtime
  observation; cloud sessions have no browser or GUI for live capture anyway.
- Targets must be in the repo (committed, LFS, or a GitHub Release) because
  cloud sessions can reach github.com and package registries but usually not
  arbitrary download URLs.

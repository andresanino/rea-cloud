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
- `scripts/rea-mcp.sh` — launches the MCP server with a supported Node.js.
- `scripts/session-start.sh` — SessionStart hook: picks/installs Node, warms the
  `rea-agents` npx cache, runs `rea mcp doctor`, reports optional engines.
- `scripts/cloud-setup.sh` — optional cloud environment Setup script: installs
  Ghidra 12.1.x, a pwntools venv and Node 24 under `/opt` (see README).

## Working here

- Use the `rea` MCP tools directly (`open_binary`, `inspect_artifact`,
  `analyze_javascript_application`, `inspect_managed_artifact`,
  `inspect_android_package`, `inspect_binary_layout`, `inspect_go_binary`,
  `inspect_rust_binary`, `inspect_pe_resources`, `inspect_packet_capture`, …).
  Use the server's actual tool list and schemas; don't call unadvertised tools.
- Do not re-run REA setup or diagnostics before every task. If the `rea` tools
  are missing, run `bash scripts/session-start.sh` and read its output. The CLI
  fallback `npx -y rea-agents@6.5.0 <command> --json` works without MCP.
- Native decompilation (pseudocode, function analysis), `inspect_binary_layout`
  and `inspect_sqlite_database` work in the cloud when the environment was set
  up with `scripts/cloud-setup.sh` and has `GHIDRA_INSTALL_DIR`,
  `REA_PWNTOOLS_PYTHON` and `REA_NODE_MAJOR` set (the SessionStart hook's
  output shows whether `GHIDRA_INSTALL_DIR` is set); on a plain cloud image
  they are unavailable and nothing in a session can install them. Static
  inspection of JS/Electron, .NET, archives, APK structure, Go/Rust metadata,
  PE resources, ELF layout, SQLite, WASM and packet captures works without an
  engine. When a question needs an engine that isn't available, say so in the
  report instead of guessing.
- Reports separate observations (cite REA Evidence IDs), inferences, and
  unknowns, and list what was not checked.
- Never execute an analyzed target unless the user explicitly asks for runtime
  observation; cloud sessions have no browser or GUI for live capture anyway.
- Targets must be in the repo (committed, LFS, or a GitHub Release) because
  cloud sessions can reach github.com and package registries but usually not
  arbitrary download URLs.

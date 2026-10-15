# Cloud verification: REA MCP in a Claude Code cloud session (2026-10-15)

REA MCP in cloud: WORKING

This report records whether the REA ("Reverse Engineer Anything", npm
`rea-agents@6.5.0`) MCP server registered by this repo starts and answers
real tool calls inside a Claude Code cloud session, with no local install.
Session facts: fresh clone of `andresanino/rea-cloud` at commit `fe683ee`
(main), Claude Code client 2.1.300 (as reported by the REA server), Linux
x86-64 cloud image, no analysis engine (Ghidra/IDA/Hopper) configured. Nothing
in the repo was changed; the target analysed was the image's own `/bin/ls`.

Every fact below is either an observation (quoted tool output, REA Evidence
IDs cited as `ev_…`), an inference, or an unknown, following the conventions
in `reports/README.md`.

## Observations

### 1. SessionStart hook output

The hook `scripts/session-start.sh` ran at session start (hook status:
success) and printed:

```
[rea-cloud] node v22.22.0 at /opt/node22/bin/node
[rea-cloud] warming rea-agents@6.5.0 in the npx cache
[rea-cloud] rea-agents 6.5.0 ready
[rea-cloud] REA MCP server starts and lists its tools
[rea-cloud] GHIDRA_INSTALL_DIR not set: no native decompilation; static JS/.NET/archive/APK/Go/Rust/PE/ELF/SQLite/WASM inspection still works
```

| Item from the hook | Value |
| --- | --- |
| Node picked | v22.22.0 at `/opt/node22/bin/node` (the image's own Node; passes the 22.19+ check) |
| REA version | rea-agents 6.5.0 (npx cache warmed) |
| `rea mcp doctor` inside the hook | passed ("REA MCP server starts and lists its tools") |
| Ghidra | `GHIDRA_INSTALL_DIR` not set, no native decompilation |
| `~/.local/node` | not created (see Environment); the hook found an acceptable Node and skipped the download |

### 2. `rea` MCP server connected to the session

- The session advertised the server's tools under the `mcp__rea__` prefix.
  Counting the advertised names gave **207 tools, 0 duplicates**, matching the
  expected 207.
- Five of them, by name: `open_binary`, `inspect_artifact`,
  `inspect_with_objdump`, `binary_session`, `analyze_javascript_application`.
  Others present include `inspect_binary_layout`, `inspect_managed_artifact`,
  `inspect_android_package`, `inspect_go_binary`, `inspect_rust_binary`,
  `inspect_pe_resources`, `inspect_packet_capture`, `inspect_sqlite_database`,
  `inspect_wasm_artifact`, `get_evidence_bundle`, `close_binary`.
- A live MCP call to `binary_session` (not the CLI) returned the server
  identity:

| Field | Value |
| --- | --- |
| server | `rea` 6.5.0, package `rea-agents` 6.5.0 |
| package root | `/root/.npm/_npx/ad9a3fdbcad992c6/node_modules/rea-agents` |
| command path | `/root/.npm/_npx/ad9a3fdbcad992c6/node_modules/.bin/rea` |
| MCP SDK | server 2.3.1, core 2.3.1 |
| negotiated protocol | 2025-11-25 |
| client seen by the server | `claude-code` 2.1.300 |
| bundled skill expected | `reverse-engineer-anything` version 42 |
| catalog counts | 153 CLI commands, 207 MCP tools, 6 MCP prompts |
| catalog digest (combined) | `405725e736ec8dc8483435b970acbf20f9f26b9f1fd25203b992f5ab4cd2a4f4` |
| alignment | `aligned`, no reasons |
| client features | elicitation form/url: true, roots: true, sampling: false |

- The same call listed provider availability. Available without an engine on
  this image: the JavaScript/Electron analyzers, browser/web capture tools,
  `inspect_electron_fuses`, `inspect_go_binary`, `inspect_rust_binary`,
  `inspect_pe_resources`, the .NET static tools (`inspect_managed_*`),
  `inspect_artifact`/`extract_artifact`, `inspect_evm_interface`,
  `inspect_pcap_capture`, `identify_flutter_build`/`inspect_dart_aot`,
  `inspect_with_objdump` (GNU objdump is on the image), the gdb tools, and
  the evidence/compare tools. Unavailable providers are listed under
  Failures.

### 3. `npx -y rea-agents@6.5.0 mcp doctor` (CLI)

Run twice (plain and `--json`), both exit code 0, both reporting:

| Check | Result |
| --- | --- |
| `healthy` | **true** |
| adapter | `production-stdio` |
| server | `rea` 6.5.0, protocol 2025-11-25 |
| tools | expected 207, **observed 207**, missing none, unexpected none, duplicates none |
| prompts | expected 6, observed 6 |
| package version | expected 6.5.0, **observed 6.5.0** |
| catalog digest | expected = observed `405725e7…2a4f4` |
| request flow | `binary_session` target-free request: ok |
| checks | initialize, inventory:tools, inventory:prompts, server-identity, request-flow: all ok |
| stderr | empty (0 bytes) |

### 4. Engine-free analysis of `/bin/ls` through the MCP tools

All calls below went through the MCP server, not the CLI. `/bin/ls` resolves
to `/usr/bin/ls`, SHA-256
`2726eb35864608ff34969fbf45ef4afcbba95eefed5ce5653c9c0124c4cd26cf`.

| # | Tool call | Outcome | Evidence ID(s) |
| --- | --- | --- | --- |
| 1 | `inspect_binary_layout` path=`/bin/ls`, detail=summary | **failed**: `provider_unavailable`, provider `pwntools-elf` needs `REA_PWNTOOLS_PYTHON` (Python with pwntools 4.15.0, pyelftools 0.33, Unicorn 2.1.2) | none |
| 2 | `open_binary` path=`/bin/ls` | **ok**: path `/usr/bin/ls`, format `elf`, kind `executable`, architecture `x86_64`, SHA-256 above. Succeeded both before and after the server restart described in Failures | none retained (by design: no Evidence record) |
| 3 | `binary_overview` | **failed**: `provider_unavailable` for operation `current_document`; candidates ghidra (not_configured), hopper (executable_missing), ida (not_configured) all rejected | none |
| 4 | `inspect_artifact` detail=summary | **ok**: provider `rea-artifact-graph`; root format `elf`, 1 node, 0 edges, coverage `complete-within-view` 2/2, source complete; limitation "Artifact has no child container entries"; next probe recorded: bind a deep native provider via `open_binary` before function-level analysis | summary view `ev_42c2b18d5e5385124f485540c8ea74affd213fce59f528a95fff0ab70515b9cd`; parent inspection `ev_a00f59eefe34d26b8d7398822368d863dae19f4d938e8fc3e68b37969d0501fd`; inventory `ev_a3ba76186284255088173fc8fc9c24ab2e902fb1dbb99e32296b818dc53efd4a` |
| 5 | `inspect_with_objdump` path=`/usr/bin/ls`, operation=file_headers (added beyond the prescribed sequence, engine-free) | **ok**: `objdump -f`, exit 0, `artifact_changed: false` | `ev_f39b7893e748911b678aad1efdd6c107545505e6eefd2c49a0d1f2e752221e2e` |
| 6 | `inspect_with_objdump` path=`/usr/bin/ls`, operation=section_headers | **ok**: `objdump -h`, exit 0, 29 sections | `ev_252a5c72a9e17751d8874da6f3bad739e31f7e6120392b41ce486fe587f5442d` |
| 7 | `get_evidence_bundle` detail=summary | **ok**: 5 retained records, all `complete-record`, authority `shipped-artifact` (the three from call 4 and the two from calls 5 and 6) | lists the five IDs above |
| 8 | `close_binary` | **ok**: `result: null`, no error | none |

Facts about `/bin/ls` observed through REA (calls 4 to 6):

- Artifact graph manifest `agm_64c3be277adaad929ae99a5644a41871b2dd195b15a692e4bb0017ae33154b3a`,
  root artifact `art_7f6f5da64ef84ecb10dc8fae4ef2c7750c5be36756d4a22abf3aa7d3b8361971`,
  graph SHA-256 `c0ec76c5353af6ae72434181fd66910f39afb987ec6ebd5a3604ad7d40a1e4d7`
  (`ev_a00f59ee…`).
- `objdump -f` (`ev_f39b7893…`): file format `elf64-x86-64`, architecture
  `i386:x86-64`, flags `0x00000150` (`HAS_SYMS, DYNAMIC, D_PAGED`), start
  address `0x6d30`.
- `objdump -h` (`ev_252a5c72…`): 29 section headers (index 0 to 28).
  `.text` is `0x141c2` bytes at VMA `0x4d70`, `.rodata` `0x516f` bytes at
  `0x19000`, `.bss` `0x1298` bytes at `0x23280`; `.gnu_debugaltlink` and
  `.gnu_debuglink` are present, so the binary is stripped with an external
  debug link. REA cleared `DEBUGINFOD_URLS` for the run, so no network
  access happened.
- The pre-run and post-run SHA-256 digests matched on every objdump call
  (`artifact_changed: false`); the target was never executed.

### 5. Inferences

- The MCP path works end to end in the cloud: the server started from the
  npx cache the hook warmed, the client negotiated protocol 2025-11-25,
  the full 207-tool catalog was advertised, and tool calls that need no
  engine returned Evidence records with stable IDs.
- Deep native analysis (`binary_overview`, pseudocode, functions, strings via
  a provider) is unavailable on this image purely for lack of an engine; the
  session itself reports Java 21 is accepted for Ghidra, so a setup script
  that unpacks Ghidra 12.1.x and exports `GHIDRA_INSTALL_DIR` is the missing
  piece (as the README already says).
- Because the hook accepts the image's Node 22.22.0, it never installs Node
  24, so `inspect_sqlite_database` stays unavailable (it needs Node 24.15+
  or 26+ for the `DatabaseSync.limits` API). Installing Node 24 in the
  environment's setup script, or preferring it in the hook, would enable it.
  No file was changed for this report.

## Failures

None of these blocks the verdict; each is a missing optional prerequisite or
an infrastructure event, with REA reporting it explicitly instead of
guessing.

1. **`inspect_binary_layout` on `/bin/ls`: `provider_unavailable`.** REA's
   message: "Set REA_PWNTOOLS_PYTHON to an absolute caller-supplied Python
   executable with pwntools 4.15.0, pyelftools 0.33 and Unicorn 2.1.2; REA
   never installs Python or packages." The image's `/usr/bin/python3`
   (3.13.16) has no `pwn` module. Fix: a setup script that creates a venv
   with those three packages and exports `REA_PWNTOOLS_PYTHON`.
2. **`binary_overview` on the open `/bin/ls`: `provider_unavailable`.** All
   three deep providers were rejected: Ghidra `not_configured`
   (`GHIDRA_INSTALL_DIR` not set; `analyzeHeadless` and the native
   decompiler missing), Hopper `executable_missing`
   (`/opt/hopper/bin/Hopper`), IDA `not_configured` (`REA_IDA_MCP_CONFIG`).
   Expected on this image.
3. **One MCP disconnect mid-session.** The session's worker process was
   restarted between call 1 and call 2 above. The `rea` server disconnected
   and reconnected on its own (server `started_at` changed from
   `2026-10-15T14:33:16.851Z` to `2026-10-15T14:43:45.283Z`); the 207 tools
   were unavailable for one turn and then advertised again. Because the
   server process was new, `/bin/ls` was re-opened with `open_binary`, which
   returned the identical identity. This is a session-infrastructure event,
   not an REA fault, but it means an open target does not survive a worker
   restart.
4. **Optional providers absent on the image** (reported by `binary_session`):
   `adb`, `apktool`, jadx (`REA_JADX_MCP_JAR`), TShark (`REA_TSHARK_COMMAND`),
   Binwalk/Unblob (`REA_BINWALK_COMMAND`/`REA_UNBLOB_COMMAND`), WABT
   (`REA_WABT_BIN_DIRECTORY`), Wakaru (`REA_WAKARU_COMMAND`), sigrok
   (`REA_SIGROK_COMMAND`), JEB (`REA_JEB_MCP_URL`), Hopper, IDA, the
   pwntools Python above, and Node 24.15+/26+ for SQLite inspection. The
   macOS-only tools (`inspect_macho`, `inspect_plist`, `inspect_signature`,
   `demangle_swift`, `list_architectures`, native UI capture) report
   `unsupported_host` on Linux, as expected.
5. No failure in the hook, the doctor, the server start, or the tool
   inventory.

## Environment

| Fact | Value |
| --- | --- |
| `node -v` | `v22.22.0` |
| `which node` | `/opt/node22/bin/node` |
| Other Node builds on the image | `/opt/node20` v20.20.0, `/opt/node21` v21.7.3; no `/opt/node24` or `/opt/node26`; `/opt/nvm` has no installed versions |
| `~/.local/node` created by the hook? | **No.** `$HOME` is `/root`; `/root/.local/node` does not exist, because the image Node passed the version check |
| `java -version` | `openjdk version "21.0.12.1" 2026-08-18`, OpenJDK Runtime Environment (build 21.0.12.1+1-1-24.04.4-Ubuntu), 64-Bit Server VM; `JAVA_HOME` seen by REA `/usr/lib/jvm/java-21-openjdk-amd64`. The image sets `JAVA_TOOL_OPTIONS` for its trust store and HTTPS proxy |
| `uname -a` | `Linux vm 6.18.44-fc-v114 #1 SMP PREEMPT_DYNAMIC @0 x86_64 x86_64 x86_64 GNU/Linux` |
| Base distribution (from the JDK build string) | Ubuntu 24.04 |
| `GHIDRA_INSTALL_DIR` | unset |
| `MCP_TIMEOUT` | `180000` (set by `.claude/settings.json`) |
| npx cache used by the server | `/root/.npm/_npx/ad9a3fdbcad992c6/node_modules/rea-agents` |
| `python3` | 3.13.16 at `/usr/bin/python3`, no pwntools |
| Analysis helpers on `PATH` | present: `objdump` (`/usr/bin/objdump`), `gdb` (`/usr/bin/gdb`), `prlimit` (`/usr/bin/prlimit`); missing: `adb`, `apktool`, `tshark`, `binwalk`, `unblob`, `sigrok-cli`, `rizin`, `rz-bin`, `frida`, `wasm-objdump` |
| `/bin/ls` per `file` | symlink target `/usr/bin/ls`: ELF 64-bit LSB pie executable, x86-64, dynamically linked, interpreter `/lib64/ld-linux-x86-64.so.2`, BuildID[sha1] `44900829b39271d878615772bb2a6ffa422f0891`, for GNU/Linux 3.2.0, stripped |
| Network | outbound HTTPS through the session proxy; `registry.npmjs.org` reachable (npx resolved `rea-agents@6.5.0`) |
| Repo state | clean clone at `fe683ee`; this report is the only file added |

## Not checked / unknowns

- Only one target (`/bin/ls`, an ELF) was analysed. The JavaScript/Electron,
  .NET, APK, Go/Rust, PE, pcap, WASM and SQLite paths were not exercised in
  this session; their availability above comes from `binary_session`'s
  capability report, not from running them.
- No runtime observation was attempted (no process was launched, per
  `CLAUDE.md`), so the gdb and Frida tools are unverified. `binary_session`
  lists the Frida tools as available even though no `frida` binary is on
  `PATH`; whether they would work was not tested.
- `scripts/session-start.sh` was not re-run by hand (the hook output was
  visible), and the environment "Setup script" caching path was not tested.
- The CLI fallback was used only for `mcp doctor`, not for an analysis
  command.
- Whether an open REA target survives an MCP reconnect without a server
  process restart is unknown; here the server process itself restarted.

# Cloud verification of the REA MCP server — 2026-10-15

**Verdict: `REA MCP in cloud: WORKING`**

Purpose: confirm that a Claude Code cloud session on this repository gets a
working `rea` MCP server (npm `rea-agents@6.5.0`) with no local install and no
analysis engine, and record what does and does not work in the cloud image.

Tools and engines used: the `rea` MCP server over stdio (launched by
`scripts/rea-mcp.sh`); REA providers `rea-artifact-graph` v1,
`rea-analysis-view` v1 and `gnu.objdump`. No Ghidra, IDA or Hopper. The CLI
(`npx -y rea-agents@6.5.0 mcp doctor`) was used only for the doctor check; the
analysis calls in section 4 went through MCP.

## Observations

### 1. SessionStart hook output

The `startup` hook (`scripts/session-start.sh`, configured in
`.claude/settings.json`) printed:

```
[rea-cloud] node v22.22.0 at /opt/node22/bin/node
[rea-cloud] warming rea-agents@6.5.0 in the npx cache
[rea-cloud] rea-agents 6.5.0 ready
[rea-cloud] REA MCP server starts and lists its tools
[rea-cloud] GHIDRA_INSTALL_DIR not set: no native decompilation; static JS/.NET/archive/APK/Go/Rust/PE/ELF/SQLite/WASM inspection still works
```

- Node picked: `v22.22.0` at `/opt/node22/bin/node` (the image's own Node;
  it satisfies the hook's 22.19+ rule, so no Node was downloaded).
- REA version: `6.5.0`, warmed into the npx cache.
- Doctor result: passed (the hook's `rea mcp doctor` exited 0).
- Ghidra status: `GHIDRA_INSTALL_DIR` not set.

### 2. The `rea` MCP server is connected

- The session's tool roster contains **207** tools named `mcp__rea__*`
  (checked by writing the names to a file: 207 lines, 207 unique). The
  server's own catalog (`binary_session.server_identity.catalog.counts`)
  reports `mcp_tools: 207`, `mcp_prompts: 6`, `cli_commands: 153`.
- Five of them: `open_binary`, `inspect_artifact`, `inspect_binary_layout`,
  `analyze_javascript_application`, `inspect_go_binary`.
- `binary_session {}` (called over MCP) reported the server identity:
  package `rea-agents 6.5.0` at
  `/root/.npm/_npx/ad9a3fdbcad992c6/node_modules/rea-agents`, server `rea`
  6.5.0 started 2026-10-15T14:46:16Z from
  `/root/.npm/_npx/ad9a3fdbcad992c6/node_modules/.bin/rea`, MCP SDK 2.3.1,
  negotiated protocol `2025-11-25`, client `claude-code 2.1.300`, expected
  skill version 42 (matches `.claude/skills/reverse-engineer-anything`),
  combined catalog digest
  `405725e736ec8dc8483435b970acbf20f9f26b9f1fd25203b992f5ab4cd2a4f4`.
- No MCP launch error, timeout or hook warning was observed.

### 3. `npx -y rea-agents@6.5.0 mcp doctor`

Run twice (text and `--json`), both exit 0:

| Field | Value |
|---|---|
| `healthy` | `true` |
| adapter | `production-stdio` |
| server | `rea` 6.5.0, protocol `2025-11-25` |
| tools | expected 207, observed **207**, missing/unexpected/duplicates: none |
| prompts | expected 6, observed 6 |
| package version | expected 6.5.0, observed **6.5.0** |
| catalog digest | expected = observed = `405725e7…cd2a4f4` |
| request flow | `binary_session` target-free request: ok |
| stderr | empty (0 bytes) |

### 4. Engine-free analysis over MCP on `/bin/ls`

| # | MCP call | Outcome | Evidence ID |
|---|---|---|---|
| 1 | `inspect_binary_layout` path=`/bin/ls`, detail=`summary` | **failed**: `provider_unavailable` (pwntools provider; see Failures) | none |
| 2 | `open_binary` path=`/bin/ls` | **ok**: resolved to `/usr/bin/ls`, format `elf`, kind `executable`, architecture `x86_64`, sha256 `2726eb35…c4cd26cf` | none (plain result) |
| 3 | `binary_overview` | **failed**: `provider_unavailable` (no Ghidra/Hopper/IDA; see Failures) | none |
| 4 | `inspect_artifact` detail=`summary` | **ok** | `ev_42c2b18d5e5385124f485540c8ea74affd213fce59f528a95fff0ab70515b9cd` (summary view) of parent `ev_a00f59eefe34d26b8d7398822368d863dae19f4d938e8fc3e68b37969d0501fd` (complete `inspect_artifact`); inventory `ev_a3ba76186284255088173fc8fc9c24ab2e902fb1dbb99e32296b818dc53efd4a` |
| 5 | `binary_session {}` | **ok**: `open: true`, `analysis_provider_binding: null`, candidates ghidra/hopper/ida all unavailable | none |
| 6 | `close_binary` | **ok**: `result: null`, session closed | none |
| 7 (extra, not in the task) | `inspect_with_objdump` operation=`file_headers`, path=`/bin/ls` | **ok**: exit 0, `file format elf64-x86-64`, `architecture: i386:x86-64, flags 0x00000150: HAS_SYMS, DYNAMIC, D_PAGED`, `start address 0x0000000000006d30`, artifact unchanged | `ev_e3aa4ee55c47d59588499501a4efc13d89b4f29631d606aec26fce47394a5441` |

Facts from `inspect_artifact` (Evidence `ev_42c2b18d…`, parent `ev_a00f59ee…`):

- Subject `ls` at `/usr/bin/ls`, format `elf`, sha256
  `2726eb35864608ff34969fbf45ef4afcbba95eefed5ce5653c9c0124c4cd26cf`.
- Artifact graph: 1 node, 1 occurrence, 0 edges, 0 integrity contradictions;
  entry kinds: 1 file. Manifest `agm_64c3be27…`, root artifact
  `art_7f6f5da6…`, graph sha256 `c0ec76c5…`.
- Coverage `complete-within-view` (2/2, exhausted); confidence `derived`,
  authority `shipped-artifact`.
- Limitations recorded by REA: "Artifact has no child container entries" and
  the inspection does not execute the artifact or claim format-specific
  semantics. One unexplored branch: `format-specific-analysis-required`, next
  probe `open_binary` with a native analysis provider.

Shell cross-checks (not REA evidence): `sha256sum /usr/bin/ls` gives the same
digest; `readlink -f /bin/ls` is `/usr/bin/ls`; `file /bin/ls` reports an ELF
64-bit LSB PIE executable, x86-64, dynamically linked, stripped.

### Inferences

- The MCP path works end to end in the cloud: Claude Code launched
  `scripts/rea-mcp.sh`, which ran `npx -y rea-agents@6.5.0 mcp` from the npx
  cache that the hook had warmed (same cache directory
  `/root/.npm/_npx/ad9a3fdbcad992c6` in the server identity), registered all
  207 tools, and served both target-free calls (`binary_session`,
  `inspect_with_objdump`) and an active-target sequence
  (`open_binary` → `inspect_artifact` → `close_binary`).
- The objdump start address `0x6d30` is consistent with a PIE (link-time
  address near zero), matching `file`'s "pie executable".
- Without a deep provider, native function-level tools (`binary_overview`,
  `analyze_function`, `list_procedures`, `procedure_pseudo_code`, `xrefs`,
  …) are advertised but fail at call time with `provider_unavailable`. That is
  the expected shape for the cloud image.

### Unknowns and what was not checked

- Nothing about the code of `ls` was analyzed: no procedures, strings, xrefs
  or pseudocode (no Ghidra/IDA/Hopper).
- `inspect_binary_layout` could not run, so the ELF section, symbol,
  relocation and mitigation facts it would produce are unknown here.
- Not exercised: `analyze_javascript_application`, `inspect_managed_artifact`,
  `inspect_android_package`, `inspect_go_binary`, `inspect_rust_binary`,
  `inspect_pe_resources`, `inspect_sqlite_database`, `inspect_wasm_artifact`
  and the packet-capture tools. Their availability below comes from
  `binary_session.tool_availability`, not from calls.
- `claude mcp list` was not run; connectivity is established by the tool
  roster and the successful calls instead.
- `binary_session` reported `alignment.state: "unknown"` because it was called
  without expected package/catalog identity inputs.

## Failures

1. **`inspect_binary_layout` → `provider_unavailable`** (category
   `unavailable`, retryable). Message: "Set REA_PWNTOOLS_PYTHON to an absolute
   caller-supplied Python executable with pwntools 4.15.0, pyelftools 0.33 and
   Unicorn 2.1.2; REA never installs Python or packages." Details: requested
   provider `pwntools-elf`, diagnostics `configuration_key:
   REA_PWNTOOLS_PYTHON`, `executable_path: ""`. Cause: the image has Python
   3.13.16 (`/usr/bin/python3`) but no pwntools (`import pwn` fails) and the
   variable is unset. Expected for the cloud image; the fallback route in
   section 4 was used instead.
2. **`binary_overview` → `provider_unavailable`** on operation
   `current_document`, provider selection `auto`, all candidates rejected:
   - `ghidra`: `not_configured` — "Set GHIDRA_INSTALL_DIR to an extracted
     Ghidra 12.1.x release directory." Java is present (OpenJDK 21.0.12.1 at
     `/usr/lib/jvm/java-21-openjdk-amd64`); the provider's `java` check stays
     `version_unresolved` because there is no Ghidra installation to resolve
     it against.
   - `hopper`: `executable_missing` — `/opt/hopper/bin/Hopper`.
   - `ida`: `not_configured` — `REA_IDA_MCP_CONFIG` unset.
   Expected: no analysis engine in the cloud image.
3. **Advertised but unavailable in this image** (from
   `binary_session.tool_availability`, not exercised):
   - `inspect_sqlite_database`: `provider_unavailable` — "SQLite inspection
     requires Node.js 24.x >=24.15 or 26+ with the native DatabaseSync.limits
     API." The server runs on Node 22.22.0, so SQLite inspection does **not**
     work here even though the hook message and `CLAUDE.md` list SQLite among
     the engine-free inspections. The hook only installs a newer Node when no
     acceptable Node is found, so Node 22 is kept. Not changed in this
     verification (no file other than this report was touched).
   - `inspect_wasm_artifact`: needs WABT 1.0.42 via `REA_WABT_BIN_DIRECTORY`.
   - `inspect_packet_capture` / `inspect_packet_fields`: need TShark 4.x via
     `REA_TSHARK_COMMAND`. (`inspect_pcap_capture` is advertised available but
     was not exercised; its guide says it needs tshark and capinfos at run
     time.)
   - Android: `inspect_android_*` need `REA_JADX_MCP_JAR`; `adb` and `apktool`
     binaries not found.
   - Firmware: `inspect_firmware_regions` / `extract_firmware` need Binwalk or
     Unblob.
   - `recover_javascript_sources`: needs Wakaru via `REA_WAKARU_COMMAND`.
   - macOS-only tools (`inspect_macho`, `inspect_plist`, `inspect_signature`,
     `demangle_swift`, `list_architectures`, `inspect_asset_catalog`, native
     UI observation): `unsupported_host` on Linux.
   - Advertised available without an engine (not exercised):
     `analyze_javascript_application`, `inspect_managed_artifact`,
     `inspect_managed_members`, `inspect_managed_native_boundaries`,
     `inspect_go_binary`, `inspect_rust_binary`, `inspect_pe_resources`,
     `inspect_electron_fuses`, `inspect_evm_interface`, `extract_artifact`,
     `inspect_web_network_capture`, `identify_flutter_build`,
     `inspect_dart_aot`, and the browser/Electron/frida/gdb/rizin session
     tools (their external binaries were not verified; cloud sessions have no
     browser or GUI).
4. No MCP launch error, no hook warning, no timeout. The 207-tool roster was
   present from the first turn.

## Environment

| Item | Value |
|---|---|
| Date (UTC) | 2026-10-15 14:46–14:52 |
| `uname -a` | `Linux vm 6.18.44-fc-v114 #1 SMP PREEMPT_DYNAMIC @0 x86_64 x86_64 x86_64 GNU/Linux` |
| OS | Ubuntu 24.04.5 LTS |
| `node -v` | `v22.22.0` |
| `which node` | `/opt/node22/bin/node` |
| `~/.local/node` | **not created**: `HOME=/root`, `/root/.local/node` does not exist. The image's Node 22.22.0 passed the hook's 22.19+ check, so `install_node` never ran. |
| `java -version` | `openjdk version "21.0.12.1" 2026-08-18`, OpenJDK Runtime Environment (build 21.0.12.1+1-1-24.04.4-Ubuntu), 64-Bit Server VM; `JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64`. `JAVA_TOOL_OPTIONS` is preset by the image (trust store and proxy settings). |
| `GHIDRA_INSTALL_DIR` | unset |
| `REA_PWNTOOLS_PYTHON` | unset; `python3` is Python 3.13.16, pwntools not installed |
| objdump | GNU objdump (GNU Binutils for Ubuntu) 2.42 at `/usr/bin/objdump` |
| rea-agents | 6.5.0; npx cache `/root/.npm/_npx/ad9a3fdbcad992c6/node_modules/rea-agents` (`package.json` version 6.5.0) |
| MCP client | `claude-code 2.1.300` (as reported by the server) |
| MCP registration | `.mcp.json`: stdio, `bash ${CLAUDE_PROJECT_DIR:-.}/scripts/rea-mcp.sh`; `.claude/settings.json`: `enableAllProjectMcpServers: true`, `MCP_TIMEOUT=180000`, SessionStart hook `scripts/session-start.sh` (timeout 540 s) |
| `CLAUDE_PROJECT_DIR` | unset inside the Bash tool's shell; the hook and the MCP launcher still ran (how the variable was resolved for them was not checked) |
| Repository | branch `claude/cloud-verification` created from `fe683ee` (= `origin/main`); only this report was added |

**`REA MCP in cloud: WORKING`**

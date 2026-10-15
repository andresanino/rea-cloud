# Cloud check: APK and packet-capture tools on the default image (2026-10-15)

Purpose: find out which of REA's Android APK and packet-capture tools work in
a Claude Code cloud session with nothing added to the image, so that
`README.md`, `CLAUDE.md` and `scripts/session-start.sh` stop over-claiming.
Companion to `reports/cloud-verification-2026-10-15.md`, which listed
`inspect_pcap_capture` as available from `binary_session`'s capability report
without running it.

Session facts: clone of `andresanino/rea-cloud` at `7f3156a` (main),
rea-agents 6.5.0 from the npx cache the hook warmed, Node v22.22.0, OpenJDK
21, `/usr/bin/prlimit` present; `tshark`, `capinfos`, `apktool` and `jadx`
absent from `PATH`; `REA_JADX_MCP_JAR`, `REA_TSHARK_COMMAND`,
`REA_CAPINFOS_COMMAND` and `REA_APKTOOL_COMMAND` unset. No analyzed file was
executed.

## Observations

### 1. `binary_session` over the MCP server

`tool_availability` groups relevant here (reason and remediation quoted):

| Tools | Surface | Available | Reason / remediation |
| --- | --- | --- | --- |
| `inspect_android_package`, `search_android_classes`, `inspect_android_class`, `inspect_android_method`, `trace_android_references` | android-provider | no | `provider_missing`: "Set REA_JADX_MCP_JAR to the absolute path of a caller-supplied jadx-headless-mcp 0.7.1 JAR. REA does not download or install it." |
| `decode_android_resources`, `inspect_apktool_client` | apktool-provider | no | `provider_unavailable`: "The selected apktool launcher was not found: apktool" |
| `inspect_packet_capture`, `inspect_packet_fields` | artifact-provider | no | `provider_missing`: "On Linux, supply TShark 4.x via absolute REA_TSHARK_COMMAND and util-linux prlimit (REA_TSHARK_PRLIMIT_COMMAND, default /usr/bin/prlimit). No active binary target or hardware is required; the tool is checked at execution." |
| `inspect_pcap_capture`, `inspect_pcap_client` | pcap-provider | **yes** | "available" (see observation 2: this does not survive execution) |
| `inspect_web_network_capture` | browser-provider | yes | "available" |
| `inspect_artifact`, `extract_artifact` | artifact-provider | after `open_binary` | `target_required` |

### 2. The tools run against handmade samples

The MCP tool calls for this step were declined by the session's permission
prompt, so the tools were run through the CLI fallback named in `CLAUDE.md`
(`npx -y rea-agents@6.5.0 <command> --json`), which is the same 6.5.0 package
root the MCP server uses. The samples live in the session scratchpad and are
not committed: `shape.apk` (764-byte ZIP with the member names an APK carries
and placeholder bytes, not a real app), `dns-query.pcap` (111 bytes, one
Ethernet/IPv4/UDP DNS query) and `ping.har` (733 bytes, one GET).

| # | Command | Outcome |
| --- | --- | --- |
| 1 | `inspect-artifact shape.apk` | **ok**: provider `rea-artifact-graph`, root format `apk`, 7 nodes (the ZIP and its 6 members; `lib/arm64-v8a/libnative.so` typed `elf`), limitation "ZIP inventory lists central-directory entries only…". Evidence `ev_2cdd2b7b1a21af8e3c42ea864dabced1c69dc6c68ba2119560a378ad47b3b880` (inspection) and `ev_a2a4f430d7c897de3d61459d018416980de3b4606ebe7a9679c38555b0b81459` (inventory) |
| 2 | `inspect-android-package shape.apk` | **failed** `capability_unavailable`, provider `jadx`: "Set REA_JADX_MCP_JAR to the absolute path of a caller-supplied jadx-headless-mcp 0.7.1 JAR. REA does not download or install it." |
| 3 | `inspect-apktool-client` | **failed** `capability_unavailable`, provider `apktool`: "The selected apktool launcher was not found: apktool. Set REA_APKTOOL_COMMAND to an absolute apktool launcher (the upstream wrapper or a java -jar script)." |
| 4 | `inspect-packet-capture dns-query.pcap --fields frame.number --fields dns.qry.name` | **failed** `capability_unavailable`, provider `tshark-capture`: "Supply absolute REA_TSHARK_COMMAND for TShark 4.x. On Linux, configure TShark 4.x through REA_TSHARK_COMMAND and util-linux prlimit through REA_TSHARK_PRLIMIT_COMMAND (default /usr/bin/prlimit)." |
| 5 | `inspect-packet-fields` | **failed**: same message as 4 |
| 6 | `inspect-pcap-client` | **failed** `capability_unavailable`, provider `pcap`: "Cannot run selected tool tshark: spawn tshark ENOENT. Supply Wireshark 4.x tshark and capinfos on PATH or through absolute REA_TSHARK_COMMAND and REA_CAPINFOS_COMMAND; REA does not install them." |
| 7 | `inspect-pcap-capture dns-query.pcap` | **failed**: same message as 6 |
| 8 | `inspect-web-network-capture ping.har har` | **ok**: decoder `har-schema/lossless-json`, 1 record, request and response reported with their numeric literals and no redactions. Evidence `ev_14c0cafc65c46646926a648db45ee599c5f43a7bf981a54c97e78cfb2e8efd88` |

## Inferences

- On the default image an APK can be inventoried as a ZIP (`open_binary` then
  `inspect_artifact`, or the CLI `inspect-artifact`) but not read: manifest
  decoding, class listing, method decompilation and reference tracing all wait
  on a jadx-headless-mcp 0.7.1 JAR (`REA_JADX_MCP_JAR`), and resource decoding
  on apktool (`REA_APKTOOL_COMMAND`). Java is not the blocker: the image's
  OpenJDK 21 meets the provider's Java 17+ requirement.
- No pcap/pcapng tool works without TShark. `inspect_packet_capture` and
  `inspect_packet_fields` need the absolute `REA_TSHARK_COMMAND` (prlimit is
  already there), and `inspect_pcap_capture` needs `tshark` and `capinfos` on
  `PATH` or through `REA_TSHARK_COMMAND` and `REA_CAPINFOS_COMMAND`. Its
  "available" entry in `binary_session` only means the provider is
  registered; the binaries are checked when the tool runs. The earlier
  report's "available without an engine" list should be read with that in
  mind.
- Recorded HAR captures are the network inspection that works with nothing
  added. `inspect_web_network_capture` also accepts SAZ, mitmproxy and qlog
  through in-process decoders; those were not exercised here.

## Not checked / unknowns

- No real APK was used, so whether `inspect_android_package` parses a genuine
  manifest once the JAR is supplied was not tested. No jadx, apktool or
  TShark install was attempted, per the hook's never-install rule.
- SAZ, mitmproxy and qlog inputs were not exercised; only HAR was.
- The CLI, not the MCP server, executed the eight commands above; the MCP
  `binary_session` call is the only MCP observation here. Both ran from the
  same package root, so different behaviour is not expected but was not
  shown.
- `extract_artifact` and `project_android_application_graph` were not run.

## Changes made from this report

`README.md`, `CLAUDE.md` and `scripts/session-start.sh` now name
`REA_JADX_MCP_JAR` and `REA_TSHARK_COMMAND` as prerequisites, keep
`inspect_artifact` and `inspect_web_network_capture` as what works, and the
hook prints whether the two variables are set, never installing anything.

# Hindsight 1.0.0 (Vectorize) — how it works, from its shipped packages (2026-10-16)

**Verdict.** Hindsight is a client–server "memory for AI agents" service. The
server is a Python web application (FastAPI served by uvicorn) backed by
PostgreSQL with the pgvector extension; by default it starts an embedded
PostgreSQL ("pg0") so nothing has to be installed. Memories live in "banks",
one per agent or user. Writing a memory (`retain`) sends text, files or images
to the server, which chunks them and uses a configured LLM to extract dated
facts and entities. Reading (`recall`) is a hybrid search over those facts
(semantic vector search, keyword search, time window and entity-graph
retrieval, then a reranker) that returns scored results. Asking a question
(`reflect`) has an LLM answer from the recalled facts plus saved "mental
models" and standing "directives", in the voice set by the bank's disposition
(skepticism, literalism, empathy), mission and background. A background worker
consolidates raw facts into "observations" and refreshes mental models on a
schedule. Clients (TypeScript and Python) are thin HTTP/JSON wrappers around a
99-operation REST API, and the server also exposes an MCP endpoint for
agent tool use. The engine's own code was not analysed (see limits), so the
pipeline description above is inferred from the API contract and
configuration surface, not observed in engine code.

## Targets

| Fact | Value |
| --- | --- |
| `targets/hindsight-client-1.0.0/` | npm `@vectorize-io/hindsight-client@1.0.0` (MIT), tarball SHA-256 `ddec2b005277cef5db1cecd73118789ccd896e4be087c43fb1e0ad04db984262`, 25 files, 1,900,974 bytes; REA directory digest `3b6d411911b8a2b876ff610cf27da2ab558575deba8704ec7b748208601a2682` |
| `targets/hindsight-all-1.0.0/` | npm `@vectorize-io/hindsight-all@1.0.0` (MIT), 5 files, 41,126 bytes; REA directory digest `ee6d20a415ff2728be59a37c8094a992558b83504f01c0e6b0638fe4f2c00ec6` |
| `targets/hindsight-api-1.0.0-whl/` | PyPI `hindsight_api-1.0.0-py3-none-any.whl` (MIT), 4,152 bytes, SHA-256 `37eb0c919f800cc5e5e84207b022b7fde20a85f8827860dc416d74f91adbd68d` |
| `targets/hindsight-all-1.0.0-whl/` | PyPI `hindsight_all-1.0.0-py3-none-any.whl` (MIT), 14,019 bytes, SHA-256 `475f768726343d717eef68c90fe5655d43267f29eb5597936555c3c6181ede2f` |
| Origin | Fetched 2026-10-16 with `scripts/fetch-target.sh` from the npm registry and files.pythonhosted.org; per-file digests in each target's `NOTES.md` and `SHA256SUMS`. Source repository named in the packages: github.com/vectorize-io/hindsight |
| Not fetched | `hindsight-api-slim` (the engine the meta-packages depend on), `hindsight-embed` (the daemon launcher), `@vectorize-io/hindsight-control-plane` (76 MB web UI), the website hindsight.vectorize.io (unreachable from the cloud session, 403 at the proxy) |
| Host | Claude Code cloud image, Ubuntu 24.04, Node v22.22.0, `rea-agents@6.5.0`; `rea` MCP tools for the analyses and views, the CLI once (`inspect-artifact` on the second wheel); artifact text read directly where cited by path and line |

Question (from the `NOTES.md` files): how does Hindsight work, what operations
does it expose, what does the client send, what does the data model look
like, how is a local instance started, and what do the Python distributions
contain and depend on.

## REA Evidence

| Record | ID |
| --- | --- |
| Client analysis, `analyze_javascript_application` (parent, retained) | `ev_0d954b9660735b27fe65581d18e0083e50b4a002bf744544741efa4a1235e14c` |
| Client summary view / module page / `src/index.ts` export item | `ev_7d1af7febd4425b77919b30d638faf9fea0e8e7be0d6ccf297f6e9f7b94d23a9` / `ev_ab30b04f2913b36f773cf28f16b0211e7c0841d526ea6ecbe1fae7b78f0ffeb7` / `ev_8b9f6bbd2a1a5238548bfac006211a2fc2c9c47ac72b967e58d63d9a66418cab` |
| hindsight-all (npm) analysis (parent, retained) | `ev_5560c3b77611fe8a22123c823a337e5695f9399bacfe978c33761ceea6ff980b` |
| hindsight-all summary view / `dist/index.js` module item | `ev_eb5a95799d269f8fe85f774c0831e67082a972078365fe7a55680b50a7704316` / `ev_142e0b36ff5208807e5545685ab73de6d52649eff105f6d7f4f298a2522209a8` |
| hindsight-api wheel, `inspect_artifact` (inventory substep) | `ev_68486008e9e7fd4218e3345a5c33c273587602f9debff417d77ab964e65852e4` (`ev_4741530554d0830dee56c238e52cccd9ea01902f11a5b6639ca5e40649c7d876`), manifest `agm_352a7550596784316c1e7425ef5c8918bfa4dd5cfeeb60a017455435ab927155`, 7 nodes |
| hindsight-all wheel, CLI `inspect-artifact` (inventory substep) | `ev_93e654c675726cfdecce8de6bc81bc8c243b889fd8ba454c12125a8ecb1cc73e` (`ev_adc227aed373b17a49e14555f15d7aab14347be22fc432ced59aec01d1904745`), 11 nodes, graph SHA-256 `3f8ee86a5665b4fdbfa485e442b7641faa12aaf6ad1384b8a1a06a89aff6a366` |

All four records carry authority `shipped-artifact`; the analyses are
confidence `derived`, the inventories `observed`. None executed anything.

## Observations

### What REA saw in the two npm packages

- **Client** (`ev_0d954b96…`): 24 relevant files, 21 parsed (TypeScript
  sources, the two `dist` bundles and their `.d.ts` files), 1,898,076 text
  bytes, 100,723 AST nodes, 2,465 findings, 0 parse failures. Semantic
  families retained: request 9, boundary 16, timer 18, call-flow 1,158,
  data-flow 15,827, closure 1,679, object-flow 2,933, promise 237,
  child-process 0, configuration 0. 7,928 unknowns. Application coverage is
  `partial` and the module page shows 579 module nodes, many sharing a path
  (`dist/index.d.mts`, `generated/sdk.gen.ts`, …) because the bundles, their
  source maps and the type declarations all resolve to the same files.
- **hindsight-all** (`ev_5560c3b7…`): 4 relevant files, 2 parsed, 37,914
  text bytes, 1,478 AST nodes, 14 findings, 0 parse failures. Families:
  child-process 10, request 4, event 8, timer 4, call-flow 12. Application
  coverage `complete`, 309 unknowns. The module item for `dist/index.js`
  (`ev_142e0b36…`) records an ESM module of 284 lines exporting
  `HindsightServer`, `consoleLogger`, `getEmbedCommand`, `silentLogger`.

### The Python distributions (wheels)

- `hindsight_api-1.0.0-py3-none-any.whl` (`ev_68486008…`) contains **no
  code**: six metadata files (`METADATA`, `RECORD`, `WHEEL`,
  `entry_points.txt`, `top_level.txt`, `LICENSE`), all hash-verified.
  `METADATA` declares one dependency, `hindsight-api-slim[all]==1.0.0`, so
  the engine lives in `hindsight-api-slim`. Its `entry_points.txt` defines
  four console scripts: `hindsight-api = hindsight_api.main:main`,
  `hindsight-admin = hindsight_api.admin.cli:main`, `hindsight-local-mcp =
  hindsight_api.mcp_local:main`, `hindsight-worker =
  hindsight_api.worker.main:main`. Its description text: "Temporal +
  Semantic + Entity Memory Architecture using PostgreSQL with pgvector";
  the server "starts at http://localhost:8888 with: REST API for memory
  operations, MCP server at `/mcp`", "uses embedded PostgreSQL by default",
  and is configured with `HINDSIGHT_API_LLM_PROVIDER` and
  `HINDSIGHT_API_LLM_API_KEY`. Its Python example calls
  `MemoryEngine().initialize()`, `ensure_bank_profile`, `set_bank_mission`,
  `retain_async`, `recall_async`, `reflect_async`.
- `hindsight_all-1.0.0-py3-none-any.whl` (`ev_93e654c6…`) depends on
  `hindsight-api-slim[all]==1.0.0`, `hindsight-client>=0.0.7` and
  `hindsight-embed==1.0.0`, with an optional `local-llm` extra
  (`hindsight-api-slim[local-llm]`). Its code, 5 files under `hindsight/`:
  - `server.py` (lines 15–17, 110–135): imports `MemoryEngine` and
    `create_app` from `hindsight_api`, builds
    `MemoryEngine(db_url="pg0", memory_llm_provider, memory_llm_api_key,
    memory_llm_model, memory_llm_base_url)`, wraps it in
    `create_app(memory, mcp_api_enabled, initialize_memory=True)` and serves
    it with `uvicorn` on `127.0.0.1` and a free port in a background thread.
    Its docstrings name `db_url="pg0"` as "embedded PostgreSQL", the LLM
    providers `groq, openai, ollama, gemini, anthropic, lmstudio`, and the
    default model `openai/gpt-oss-120b`.
  - `embedded.py`: `HindsightEmbedded` drives the same daemon manager as
    the `hindsight-embed` CLI (`get_embed_manager()`), stores profile data in
    `~/.pg0/instances/hindsight-embed-{profile}/`, passes
    `HINDSIGHT_API_LLM_PROVIDER/_API_KEY/_MODEL/_BASE_URL`,
    `HINDSIGHT_API_LOG_LEVEL`, `HINDSIGHT_EMBED_DAEMON_IDLE_TIMEOUT` and
    `HINDSIGHT_EMBED_API_DATABASE_URL`, serves a UI on `daemon port + 10000`,
    and exposes `banks`, `mental_models`, `directives` and `memories`
    namespaces.

### How the Node package starts a local instance

`targets/hindsight-all-1.0.0/dist/index.js` (REA: 10 child-process
relations, 4 request relations, 4 timers):

- Lines 5–11: the daemon command is `uvx hindsight-embed@<version|latest>`,
  or `uv run --directory <path> hindsight-embed` for a local checkout. The
  package README states `uv`/`uvx` must be on `PATH` and Node must be 22 or
  newer.
- Lines 32–36: defaults port `8888`, host `127.0.0.1`, profile `default`,
  readiness timeout 30 s polled every 1 s.
- Lines 150–171: `profile create <profile> --merge --port <port>
  [--env K=V …]`, forwarding caller-supplied environment variables into the
  profile file.
- Lines 193–207: `daemon --profile <profile> start`; lines 87–112:
  `daemon --profile <profile> stop` with a 5 s timeout that never throws.
- Lines 255–276 and 113–123: readiness and health are `GET <baseUrl>/health`
  with `fetch`.
- Lines 132–137 and 180–191: on macOS it sets
  `HINDSIGHT_API_EMBEDDINGS_LOCAL_FORCE_CPU=1` and
  `HINDSIGHT_API_RERANKER_LOCAL_FORCE_CPU=1`, so the server runs a local
  embedding model and a local reranker.
- The README says the package "deliberately does not ship an HTTP client";
  `@vectorize-io/hindsight-client` talks to `server.getBaseUrl()`.

### The client: what it sends and where

- Layout (`targets/hindsight-client-1.0.0/`): `generated/` is a code
  generator's output from the server's OpenAPI description (`sdk.gen.ts`,
  `types.gen.ts` with 667 exported types, `client/`, `core/`); `src/index.ts`
  wraps it in a `HindsightClient` class (line 343) with 45 methods; `dist/`
  holds the CommonJS and ESM bundles.
- Transport (`src/index.ts`): HTTP/JSON over `fetch` to a `baseUrl`; an
  optional API key is sent as `Authorization: Bearer <key>` (lines 356–357);
  the `User-Agent` is `hindsight-client-typescript/<version>` (lines 92,
  352–354); requests that come back `429` or `503` are retried up to 3
  attempts, honouring `Retry-After` with jitter (lines 95–156). REA recorded
  the `retryOnCapacity` export at lines 122–156 (`ev_8b9f6bbd…`).
- Operations in `generated/sdk.gen.ts`: **99**, 46 GET, 29 POST, 13 DELETE,
  9 PATCH, 2 PUT. Every bank operation lives under
  `/v1/default/banks/{bank_id}/…`; the rest are `/health`, `/health/live`,
  `/health/ready`, `/metrics`, `/version`, `/v1/bank-template-schema`,
  `/v1/default/chunks/{chunk_id}` and `/v1/default/files/download/{key}`.
  Grouped:

| Area | Paths under `/v1/default/banks/{bank_id}` |
| --- | --- |
| Memories | `POST /memories` (retain), `POST /files/retain`, `POST /memories/recall`, `GET /memories/list`, `GET/PATCH /memories/{id}`, `GET /memories/{id}/history`, `DELETE /memories/{id}/observations`, `POST /memories/dry-run-extract`, `DELETE /memories` |
| Reflection | `POST /reflect`, `POST /prompts/preview` |
| Bank identity | `GET/PUT /profile` (disposition), `POST /background`, `PUT/PATCH/DELETE` on the bank, `GET/POST/PATCH/DELETE /aliases…`, `GET/PATCH/DELETE /config`, `POST /health/llm` |
| Mental models | `GET/POST /mental-models`, `GET/PATCH/DELETE /mental-models/{id}`, `/refresh`, `/dry-run-refresh`, `/clear`, `/history` |
| Directives | `GET/POST /directives`, `GET/PATCH/DELETE /directives/{id}` |
| Knowledge base | `/knowledge-base/tree`, `/folders`, `/pages`, `/pages/{id}`, `/search`, `/nodes/{id}`, `/export` |
| Documents and chunks | `GET /documents`, `GET/PATCH/DELETE /documents/{id}`, `/documents/{id}/chunks`, `/documents/{id}/reprocess`, `/document-transfer…`, `GET /tags` |
| Entities and graphs | `GET /entities`, `GET /entities/{id}`, `POST /entities/{id}/regenerate`, `GET /entities/graph`, `GET /graph` |
| Observations and consolidation | `DELETE /observations`, `GET /observations/scopes`, `POST /consolidate`, `POST /consolidation-strategies/preview`, `POST /consolidation/recover` |
| Async operations | `GET /operations`, `GET/DELETE /operations/{id}`, `/retry`, `/delete` |
| Transfer, templates, clone | `GET /export`, `POST /import`, `POST /transfer/export`, `POST /transfer/import`, `POST /clone`, `GET /attachments/{id}` |
| Observability | `GET /stats`, `GET /stats/memories-timeseries`, `GET /audit-logs`, `/audit-logs/stats`, `GET /llm-requests`, `/llm-requests/stats`, `GET/POST /webhooks`, `PATCH/DELETE /webhooks/{id}`, `/webhooks/{id}/deliveries` |

- Data model (`generated/types.gen.ts`, exact field names):
  - `RetainRequest { items: MemoryItem[], async, document_tags, operation_id }`;
    `MemoryItem { content: string | (text|image|file) blocks, timestamp,
    context, metadata, document_id, entities[{text,type}], resolve_entities,
    tags, observation_scopes, strategy, update_mode: replace|append }`;
    `RetainResponse { success, items_count, async, operation_id(s), usage }`.
  - `RecallRequest { query, types, prefer_observations, budget: low|mid|high,
    max_tokens, trace, query_timestamp, include{entities, chunks,
    source_facts}, tags, tags_match, tag_groups, min_scores, temporal_window
    {start,end} }`; `RecallResult { id, text, type, entities, context,
    occurred_start, occurred_end, mentioned_at, document_id, chunk_id, tags,
    source_fact_ids, scores{final, reranker, semantic, keyword}, attachments }`.
  - `ReflectRequest { query, budget, context, max_tokens, include,
    response_schema, tags…, apply_all_directives, fact_types:
    world|experience|observation, exclude_mental_models(_ids) }`;
    `ReflectResponse { text, based_on{memories, mental_models, directives},
    structured_output, usage{input/output/total/cached/thoughts tokens},
    trace }`.
  - `CreateBankRequest { name, disposition{skepticism, literalism, empathy},
    mission, background, reflect_mission, retain_mission,
    retain_extraction_mode, retain_custom_instructions, retain_chunk_size,
    retain_structured_chunk_size, retain_max_attachments_per_chunk,
    enable_observations, observations_mission, enable_text_search,
    enable_temporal_retrieval, enable_graph_retrieval, enable_reranking }`.
  - `MentalModelResponse { name, source_query, content, tags, max_tokens,
    trigger{mode: full|delta, refresh_cron, refresh_after_consolidation,
    min_refresh_interval_seconds, …}, last_refreshed_at, is_stale }`;
    `DirectiveResponse { name, content, priority, is_active, tags }`;
    `ExtractedFact { text, fact_type, occurred_start, occurred_end, entities,
    chunk_index }` (returned by dry-run-extract);
    `OperationStatusResponse.status: pending|processing|completed|failed|
    cancelled|not_found`; `CreateWebhookRequest { url, secret, event_types }`.
  - `VersionResponse.features` flags: `observations, mcp, worker,
    bank_config_api, bank_llm_health, file_upload_api, document_export_api,
    document_import_api, audit_log, llm_trace, store_document_text`.
- The package README's own summary matches: `retain`, `retainBatch`,
  `recall` (with `budget`), `reflect` ("using the bank's identity and
  memories"), `createBank` ("with personality"), `getVersion`.

## Inferences

Everything here is inferred from the contract and configuration names above;
the engine code (`hindsight-api-slim`) was not read.

- **Architecture.** A Python API server (FastAPI + uvicorn) in front of
  PostgreSQL with pgvector, started one of three ways: `pip install
  hindsight-api` and the `hindsight-api` command; the Python `hindsight-all`
  in-process `Server`; or the Node `@vectorize-io/hindsight-all`, which
  spawns the `hindsight-embed` daemon through `uvx`. All default to an
  embedded PostgreSQL ("pg0") on `127.0.0.1:8888`, with a UI on port + 10000
  and MCP at `/mcp`. A separate `hindsight-worker` process exists, which
  together with the `operations` endpoints and the `async` retain flag
  indicates a job queue for ingestion and consolidation.
- **Retain.** Content is chunked (`retain_chunk_size`), an LLM extracts
  facts of type `world`, `experience` or `observation` with time ranges and
  entities (`ExtractedFact`), steered by `retain_mission`,
  `retain_extraction_mode` and `retain_custom_instructions`; facts are
  stored with embeddings (semantic), a keyword index, temporal fields and
  entity links, and grouped under documents, chunks and tags.
- **Recall.** A hybrid retrieval: semantic, keyword, temporal and entity-graph
  retrieval, each switchable per bank, followed by a reranker, yielding
  `scores{semantic, keyword, reranker, final}`; `budget` trades effort for
  latency; `prefer_observations` favours consolidated summaries over raw
  facts.
- **Reflect.** An LLM composes an answer from recalled facts, mental models
  and directives; the bank's `disposition`, `mission` and `background` shape
  the answer; `response_schema` yields structured output; `based_on` and
  `trace` make the grounding inspectable.
- **Memory maintenance.** "Observations" are consolidated summaries produced
  per scope (tags) by a background job (`consolidate`, strategies,
  recovery); "mental models" are saved reflections re-run on a cron or delta
  trigger. Together they are the "memory that learns" of the tagline.
- **LLM split.** Embeddings and reranking run locally (the CPU-forcing
  flags), while fact extraction and reflection use the configured provider
  (groq, openai, ollama, gemini, anthropic, lmstudio), so the service works
  with any of those and can run fully local with the `local-llm` extra.

## Unknowns and limits

- `hindsight-api-slim` and `hindsight-embed` were not fetched. The extraction
  prompts, ranking formula, consolidation logic and database schema are
  therefore not observed; fetching the slim wheel (PyPI is reachable) and
  reading its `hindsight_api` package would resolve this.
- The control-plane web UI (`@vectorize-io/hindsight-control-plane`, ISC,
  76 MB) and the hosted site were not analysed; the site is unreachable from
  the cloud session.
- Static analysis only: nothing was executed, no network traffic observed,
  and nothing verifies that the server behaves as its types describe.
- REA's client semantic graph is `partial` with 7,928 unknowns, mostly from
  duplicated module paths and library data flow; function fingerprints were
  not needed for this question. REA's module views do not page relation
  families, so the spawn and request facts were read from `dist/index.js`
  and corroborated by REA's family counts only.
- The REA CLI route was used once (second wheel) because `open_binary` binds a
  single active target; both routes return the same Evidence shape.

## Reproduce

```bash
# intake (writes targets/<name>/NOTES.md and SHA256SUMS; executes nothing)
bash scripts/fetch-target.sh hindsight-client-1.0.0 npm:@vectorize-io/hindsight-client@1.0.0 "How does Hindsight work…"
bash scripts/fetch-target.sh hindsight-all-1.0.0 npm:@vectorize-io/hindsight-all@1.0.0 "How is a local Hindsight instance started…"
bash scripts/fetch-target.sh hindsight-api-1.0.0-whl "https://files.pythonhosted.org/packages/81/95/bd973e34a947f09f2634d2e4ae7da301a7fd0995faed6f4baff4c493fed3/hindsight_api-1.0.0-py3-none-any.whl" "…"
bash scripts/fetch-target.sh hindsight-all-1.0.0-whl "https://files.pythonhosted.org/packages/c9/20/c5f244a78158b7d1cb5a1ed61267422f9d09cdfa7852dcca90c6f516f654/hindsight_all-1.0.0-py3-none-any.whl" "…"

# REA (MCP tools in the session): analyze_javascript_application {input_path: <target dir>, detail: "summary"}
#   then inspect_analysis_view {source: {kind: "retained-evidence", evidence_id: <parent>}, view: {kind: "page", collection: "modules", offset: 0, limit: 32}}
#   open_binary {path: <wheel>} ; inspect_artifact {} ; close_binary {}
# CLI equivalents:
npx -y rea-agents@6.5.0 analyze-javascript-application "$PWD/targets/hindsight-client-1.0.0" --json > client.json
npx -y rea-agents@6.5.0 inspect-artifact "$PWD/targets/hindsight-all-1.0.0-whl/hindsight_all-1.0.0-py3-none-any.whl" --json > all-whl.json

# operation table from the generated SDK (method, path, name)
node -e 'const L=require("fs").readFileSync("targets/hindsight-client-1.0.0/generated/sdk.gen.ts","utf8").split(/\r?\n/);let n="",m="";for(const r of L){const l=r.trim();if(l.startsWith("export const "))n=l.slice(13).split(" ")[0];for(const k of ["get","post","put","patch","delete"])if(l.includes("."+k+"<"))m=k.toUpperCase();const u=l.indexOf("url:");if(u>=0){const s=l.slice(u+4).trim();console.log(m,s.slice(1,s.indexOf(s[0],1)),n)}}'

# wheel metadata
unzip -p targets/hindsight-api-1.0.0-whl/hindsight_api-1.0.0-py3-none-any.whl '*/METADATA' '*/entry_points.txt'
unzip -p targets/hindsight-all-1.0.0-whl/hindsight_all-1.0.0-py3-none-any.whl hindsight/server.py
```

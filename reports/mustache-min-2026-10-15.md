# mustache.min.js — reverse engineering and rebuild (2026-10-15)

**Verdict: the artifact was fully reconstructed. The rebuild
(`rebuilds/mustache/mustache.mjs`) is behaviourally identical to the shipped
minified build on 67 curated cases and 3,000 generated templates — same
output, same parse tokens, same errors.**

## Target

| Fact | Value |
| --- | --- |
| File | `targets/mustache-min/mustache.min.js` |
| Origin | npm `mustache@4.2.0`, `package/mustache.min.js` (MIT), fetched 2026-10-15 |
| Size / SHA-256 | 11,790 bytes / `d7fd0603512461e8edbd81686bead2ab82df3389b9cca235dd9d5b408848e02a` |
| Rule | Only the minified artifact was analysed. The package's unminified `mustache.js` was neither copied into the repo nor read. |
| Host | Windows 11, Node v24.14.0, REA `rea-agents@6.5.0` via the CLI route (`analyze-javascript-application`); the `rea` MCP server was registered but not connected in this session, and the CLI returns the same Evidence record directly |

Questions (from `targets/mustache-min/NOTES.md`): (1) public API, (2) how
templates are tokenised and parsed, (3) how they are rendered, (4) can a clean
implementation be rebuilt and proven equivalent. All four are answered below.

## Observations

Everything in this section is a static observation of the artifact, cited to
REA Evidence or to a column range on the artifact's single line.

### REA Evidence

| Record | ID |
| --- | --- |
| Application analysis (`analyze_javascript_application`, provider `rea-javascript-application` v1, authority `shipped-artifact`, confidence `derived`) | `ev_6aa2295d0c267f44871567f9870fc659a82f30ec36616bb7b5e2abdd136409dd` |
| Summary view of that record (`inspect_analysis_view`, `view.kind: summary`) | `ev_0744943e1a1e6c3d8dcc59bf931ed0d0a13f77a6efd3e91478ee5b53daec7498` |
| Inventory manifest / directory root digest | `agm_40f078a0158ee685ba975ec8faff1dc274c64498633f4c97aa709616a1e9b1f5` / `a5bcbb5384db6e12958d511068ef3d3e9099e05e0ae0e6c17cef1a05c4fb4fff` |

- Inventory: 1 relevant file, 11,790 text bytes read, 1 JavaScript file
  parsed, 2,505 AST nodes visited, 0 parse failures, 0 integrity
  contradictions.
- Semantic graph: 1,838 nodes — expression 1,281, binding 130, call-site 125,
  property-slot 123, parameter 74, **function 47**, return-site 44, literal 8,
  boundary 5, module 1 — with 2,059 relations and 47 function fingerprints.
- 549 unknowns, all static value-flow families: object-flow 242, data-flow
  203, call-flow 101, boundary 3 (example: "Binding config has no constant
  initializer" — the values come from callers, as expected for a library).
- Electron/IPC summary is all zeros (no BrowserWindow, preload, contextBridge,
  IPC, utility process or native addon): this is a plain library bundle.
- The 8 literal nodes are the HTML entity strings `&amp; &lt; &gt; &quot;
  &#39; &#x2F; &#x60; &#x3D;` — the complete escaping table.
- Boundary nodes: `String` (global coercion) and `parse` (three candidates):
  the artifact's own `parse` entry points, recorded as validation/parse
  boundaries.
- The artifact is whitespace-minified but **not name-mangled**: REA's
  function nodes carry the original identifiers (`parseTemplate`,
  `renderSection`, …). In a mangled build the same column-anchored function
  inventory would still exist, but names would have to be inferred from
  behaviour.

### Function inventory (47 functions, from the Evidence's `function` nodes)

Columns are on the artifact's single line.

| Role | Functions (columns) |
| --- | --- |
| Wrapper | UMD wrapper `(anonymous)` 1–209; factory `(anonymous)` 216–11787 |
| Helpers | `isArrayPolyfill` 312–399, `isFunction` 400–462, `typeStr` 462–523, `escapeRegExp` 523–613, `hasProperty` 613–705, `primitiveHasOwnProperty` 705–872, `testRegExp` 909–974, `isWhitespace` 994–1061 |
| Escaping | `escapeHtml` 1175–1296, `fromEntityMap` 1248–1294 |
| Parser | `parseTemplate` 1403–3863 (with inner `stripSpace` 1603–1738, `compileTags` 1783–2195), `squashTokens` 3863–4187, `nestTokens` 4187–4649 |
| Scanner | `Scanner` 4649–4721, `eos` 4743–4780, `scan` 4804–4991, `scanUntil` 5020–5274 |
| Context | `Context` 5275–5380, `push` 5403–5453, `lookup` 5479–6220 |
| Writer | `Writer` 6221–6408 (cache `set` 6273–6320, `get` 6325–6367, `clear` 6374–6406), `clearCache` 6436–6530, `parse` 6554–6888, `render` 6913–7168, `renderTokens` 7199–7901, `renderSection` 7933–8861 (inner `subRender` 8067–8149), `renderInverted` 8894–9121, `indentPartial` 9153–9477, `renderPartial` 9509–10015, `unescapedValue` 10048–10150, `escapedValue` 10181–10417, `rawValue` 10444–10485, `getConfigTags` 10517–10666, `getConfigEscape` 10700–10832 |
| Public API | `templateCache` setter 11023–11082 and getter 11083–11138, `clearCache` 11189–11245, `parse` 11261–11333, `render` 11350–11670 |

### Behaviour read from the artifact

Read on a pretty-printed copy (prettier 3.6.2, whitespace only) guided by the
inventory above; `ev_6aa2295d…` anchors every function named here.

**Public API (question 1).** The UMD wrapper exports one object to
`module.exports`, AMD `define`, or `global.Mustache`. Its members: `name`
"mustache.js", `version` "4.2.0", `tags` `["{{","}}"]`, `escape` (the HTML
escaper, replaceable), `parse(template, tags)`, `render(template, view,
partials, config)`, `clearCache()`, the classes `Scanner`, `Context`,
`Writer`, and a `templateCache` accessor that proxies to a default `Writer`.
`render` throws a `TypeError` with a fixed message when `template` is not a
string.

**Tokeniser and parser (question 2).** `parseTemplate` walks the template
with a `Scanner`, emitting one `["text", char, start, end]` token *per
character* and, for each tag, `[type, key, start, end]`. Tag types come from
the sigil regex `#|\^|\/|>|\{|&|=|!`, defaulting to `"name"`; `{{{x}}}` is
folded into type `"&"`; `{{=<% %>=}}` recompiles the opening/closing tag
regexes on the fly (`compileTags`, which throws `Invalid tags: …` unless it
gets exactly two). Partials get a 7-element token carrying `indentation`,
`tagIndex` and `lineHasNonSpace`. Per-character text tokens exist so that
`stripSpace` can delete the whitespace of a *standalone* line (a line whose
only content is non-value tags) when the newline arrives; `squashTokens`
then merges the surviving characters and `nestTokens` moves each section's
body into `token[4]` and stores the closing offset in `token[5]`. Errors:
`Unclosed tag at N`, `Unopened section "x" at N`, `Unclosed section "x" at
N`.

**Renderer (question 3).** `Context` is a linked view stack with a per-node
cache; `lookup` resolves dotted names by walking into the view, declares a hit
only when the last segment exists (`in` for objects, own property for
primitives), falls back to parent contexts, and calls function values with
the view as `this`. `Writer.parse` caches tokens under
`template + ":" + tags.join(":")` (cache replaceable or disabled via
`templateCache`). `renderTokens` dispatches on token type: `#` → arrays
render the body per item, objects/strings/numbers once with the value
pushed, functions are lambdas called with the raw body text (sliced from
the original template by `token[3]..token[5]`) and a `subRender`, any other
truthy value renders the body in place; `^` renders only for falsy values
and empty arrays; `>` looks the partial up in a map or function, re-indents
a standalone partial line by line (`indentPartial`), parses it with the
config tags and renders it in the same context; `name` escapes (numbers skip
the *default* escaper only); `&` and `{` are raw; `text` is copied.
`config` may be a `[open, close]` array or `{ tags, escape }`.

## Inferences

- The one-token-per-character design exists to implement the Mustache
  standalone-line rule cheaply; it is an implementation choice, not a
  behavioural requirement, but the rebuild keeps it so that `parse()` output
  (token offsets included) matches the artifact exactly.
- `version: "4.2.0"` inside the artifact matches the npm version it was
  fetched from; the string is data in the bundle, not proof of provenance.
- The 549 unknowns do not hide behaviour: every unknown value is a caller
  input (`view`, `partials`, `config`, template text), which is why the
  verification below uses execution on chosen inputs rather than more static
  analysis.

## Unknowns and limits

- Static analysis never executed the artifact; REA's record says so
  explicitly. Runtime behaviour was established only by the differential tests
  below, which *do* execute both implementations on chosen inputs.
- REA's own source-vs-bundle check (`import-reference-source` +
  `compare-source-to-bundle`) could not run here: the importer reports
  `unsupported_host` on Windows ("Import the source tree with REA on Linux
  (including WSL) or macOS"), and WSL is not installed. It can be run from a
  cloud session on this repo (Linux image); see the follow-up proposed in the
  session log.
- Equivalence is demonstrated on the corpus and the generator grammar, not
  proven for all inputs. Known inherent differences: the rebuild's `Context`
  class is a different object from the artifact's, so a `Context` instance
  from one implementation passed as `view` to the other is treated as a plain
  object; and V8 `TypeError` messages embed source text, so the tests compare
  those with whitespace removed.

## Rebuild (question 4)

`rebuilds/mustache/mustache.mjs` — ~600 lines including comments, ES module, `Scanner`/`Context`/
`Writer` as classes, every stage commented, same token shapes, regexes, lookup
rules, whitespace handling, cache key and error messages as the artifact.
Deliberate design differences from the observed code (not behaviour): ESM
instead of a UMD wrapper, `Array.isArray` used directly instead of the
`[object Array]` polyfill, `const`/`let` and arrow functions.

## Verification

`rebuilds/mustache/test/differential.test.mjs` loads the shipped artifact
(`require` of the UMD file) and the rebuild side by side, and for each input
compares `{ok, value}` or `{ok, error}` of `render()` **and** of `parse()`:

| Suite | Cases | Result |
| --- | --- | --- |
| Curated corpus: variables, escaping, triple/ampersand, numbers with default and custom escapers, dotted names, primitive own properties, implicit iterator, list/object/string/number/boolean/null sections, nested context fallback, inverted sections, section and variable lambdas (`this`, raw text, null return), partials (map, function, missing, standalone-indented, tab-indented, inline, recursive, context inheritance), comments, inline/standalone/nested set-delimiters and regex-special delimiters, config tags as array and object, standalone-line whitespace rules incl. CRLF and mixed indentation, unicode, non-object views, and 10 error cases (unclosed/unopened/mismatched tags, invalid delimiters, non-string templates, null views) | 67 (57 render, 10 throw) | pass |
| Escape function and exported members | — | pass |
| `templateCache` replacement and disabling: identical cache keys and contents on both | — | pass |
| Generated templates from a grammar (text, all tag kinds, nested sections to depth 3, set-delimiter changes mid-template, deliberately broken fragments), seed 20261015 | 3,000 (output, tokens and errors all agree) | pass |

```
node --test rebuilds/mustache/test/differential.test.mjs
✔ curated corpus: identical render output, parse tokens and errors
✔ escape function and exports match
✔ template cache: same keys, can be replaced and disabled
✔ generated templates: 3000 cases agree (output, tokens and errors)
ℹ tests 4  pass 4  fail 0
```

## Reproduce

```bash
# 1. static analysis (Evidence record, ~7 s)
npx -y rea-agents@6.5.0 analyze-javascript-application "$PWD/targets/mustache-min" --json > analysis.json
# 2. summary view with its own Evidence ID
node -e 'const fs=require("fs");fs.writeFileSync("view.json",JSON.stringify({source:{kind:"inline",evidence:JSON.parse(fs.readFileSync("analysis.json","utf8"))},view:{kind:"summary"}}))'
npx -y rea-agents@6.5.0 inspect-analysis-view view.json --json
# 3. prove the rebuild
node --test rebuilds/mustache/test/differential.test.mjs
```

## REA source-vs-bundle comparison (Linux, 2026-10-15)

Follow-up to the open item in "Unknowns and limits": the
`import-reference-source` step that Windows refused ran here on the cloud
image (Ubuntu 24.04, Node v22.22.0, `rea-agents@6.5.0` via the CLI route,
which returns the same Evidence records as the MCP tools). Evidence IDs below
are from this run; they are not the Windows IDs above, because every run
produces its own records.

### Evidence (this run)

| Record | ID |
| --- | --- |
| Static analysis (`analyze-javascript-application`, provider `rea-javascript-application` v1, authority `shipped-artifact`, confidence `derived`) | `ev_94b4525be5fb814702b9784ea382a9cf7c15e385b56d5e9167ae87ac11a1f0f2` |
| Application graph / semantic graph inside it | `jag_a98615b6277c5e3cf708cdd2d323a46ca5c0650aaf31797a79da16fb63f48dcb` / `jsrg_c2a12c1905c19fa9aa58cf8f137a4df184e63d207b9e8e1e50a1442cd5b1e06c` |
| Inventory manifest / directory root digest | `agm_2e95ae34c36d3d5c5fb7ed42d80a65b4ecde2885edfaead9c3fa1f3bf3756c20` / `a5bcbb5384db6e12958d511068ef3d3e9099e05e0ae0e6c17cef1a05c4fb4fff` (root digest identical to the Windows run) |
| Historical reference import (`import-reference-source`, schema `HistoricalSourceGraph`, authority `historical-reference`; this document carries no Evidence ID, its identity is the root digest) | `root_sha256` `9ec839dfed168fff50c766a69a14c07cb353ce3918698121af68d5822526ec50` |
| Comparison (`compare-source-to-bundle`, provider `rea-javascript-application-workflows` v1, predicate `rea.source-to-bundle-comparison`, authority `analyst-inference`, confidence `inferred`) | `ev_94c3649f473ead15eaa8f8ceffbdf685a73f59d302dab251c3931df5f6afa2fc` (`comparison_id` `stbc_0bdfedc3f6381e64f08f6ccc1f18e09fedb822372336db88fe843d4c435ac2eb`) |

### Observations

**Step 1, static analysis re-run.** Same inventory and graph shape as the
Windows run: 1 relevant file, 11,790 text bytes, 1 JavaScript file parsed,
2,505 AST nodes, 0 parse failures, 0 integrity contradictions; semantic graph
of 1,838 nodes (function 47, expression 1,281, binding 130, call-site 125,
property-slot 123, parameter 74, return-site 44, literal 8, boundary 5,
module 1), 2,059 relations, 47 function fingerprints, 549 unknowns. All 47
`function` nodes carry `identity.artifact_sha256 =
d7fd0603512461e8edbd81686bead2ab82df3389b9cca235dd9d5b408848e02a` (the
artifact's SHA-256) with `module_path: mustache.min.js` and their column
range, and the graph's `javascript-asset` node for `mustache.min.js` has
identity strategy `content-digest` with the same SHA-256 and 11,790 bytes.

**Step 2, reference import.** `rebuilds/mustache` imported without refusing
anything, so no temporary directory was needed. Result: schema
`HistoricalSourceGraph`, `inventory_state: partial`, 4 entries, 6
relationships, 0 parse failures, 0 exclusions, languages JavaScript and
Markdown, VCS head `21844df`:

| Entry | Kind | Classification | SHA-256 / state |
| --- | --- | --- | --- |
| `README.md` | file, 1,066 bytes | documentation | `6233ee8b…` hashed |
| `mustache.mjs` | file, 19,473 bytes | source | `264c29b18e8dc8447b5d1dbbb178960ce5117aa23b5eaf309ec9ae28179e59ec` hashed |
| `test` | directory | source, test | enumerated |
| `test/differential.test.mjs` | file, 13,776 bytes | source, test | `5ec130407e5b727bb020493f9849200803aa61c109ec4294f29c1ec035ec07f9` hashed |

The relationships are the test file's imports: `mustache.mjs` (internal) and
`node:assert/strict`, `node:module`, `node:path`, `node:test`, `node:url`
(external), all `parsed`. The only limitation recorded is host-level: "Path
identity is revalidated around operations; Node lacks portable
descriptor-relative openat traversal, so a syscall-boundary pathname race
remains."

**Step 3, comparison input.** `/tmp/compare-input.json` was built by a Node
script as `{"reference": <import output>, "application": <analysis record>}`;
the import output is the `HistoricalSourceGraph` itself (not wrapped), and no
field of either document was edited. Validation accepted it as is. Running
the comparison a second time from the same two inputs produced a
byte-identical record with the same Evidence ID.

**Step 4, comparison result** (`normalized_result` of `ev_94c3649f…`):

| Measure | Value |
| --- | --- |
| Scoring model | `rea-source-to-bundle-signals`, minimum candidate score 20; weights: exact-source-digest 100, source-map-original-path 70, current-path-exact 60, current-path-suffix 40, unicode-equivalent-path 20, basename-match 20, language-extension 5 |
| Summary | unchanged 0, modified 0, removed 0, split 0, merged 0, duplicated 0, **unknown 2** |
| `mustache.mjs` | status `unknown`, confidence `unknown`, 0 candidates: "No candidate was observed, but incomplete input or graph coverage prevents a removal claim." |
| `test/differential.test.mjs` | same |
| Unmapped bundle nodes | 3 of 3: the `mustache.min.js` asset (content digest `d7fd0603…`), its `source-module` node, and its CommonJS `default` export node |
| Coverage | status `partial`; reference inventory `partial`; application graph `complete`; 2 source files retained; 3 application nodes retained; **0 candidate evaluations** |

In plain language:

- **Digest: no match.** The rebuild's bytes (`264c29b1…`) and the bundle's
  (`d7fd0603…`) differ, as they must for a rewrite; an exact digest is the
  only signal this tool reports as `unchanged`.
- **Structural fingerprint and semantic matches: none attempted.** This
  comparison maps *files* by identity signals (digest, source-map path, path,
  basename, extension). It does not read the 47 function fingerprints in the
  analysis record (normalized-AST, control-flow, relation-shape and
  literal-set hashes), so it produced no function-level matches and no
  function-level mismatches. The expectation that ESM/class/formatting
  differences would make fingerprints differ could therefore not be tested
  with this tool.
- **Unmatched: everything.** Both reference source files are `unknown` and
  all three bundle nodes are unmapped. The tool did *not* call the source
  files `removed`, because a removal claim needs a `complete` reference
  inventory and this one is `partial`.
- **Limitations recorded** (verbatim, from the record): "Artifact identity is
  unavailable for this observation."; "Static digest and location signals do
  not establish runtime behavior, semantic equivalence, or absence of
  dynamically generated modules."; "Historical source inventory is partial;
  unmatched files remain unknown."; the openat path-race note above; and the
  five static-analysis limitations inherited from `ev_94b4525b…` (inert
  parsing, no bootstrap execution, static relationships do not prove runtime
  execution, dynamic paths may stay unresolved, Webpack/Rspack factories read
  from AST literals).

**Step 5, differential test on this image** (Node v22.22.0):

```
node --test rebuilds/mustache/test/differential.test.mjs
ok 1 - curated corpus: identical render output, parse tokens and errors
ok 2 - escape function and exports match
ok 3 - template cache: same keys, can be replaced and disabled
ok 4 - generated templates: 3000 cases agree (output, tokens and errors)
# tests 4
# pass 4
# fail 0
```

4 of 4 tests pass, 0 fail: the 67 curated cases (57 render, 10 throw) and the
3,000 generated templates agree on output, tokens and errors, as on Windows.

### Inferences

- **Why the reference inventory is `partial`.** Read from the installed
  package (`dist/application/ReferenceSourceImport.js` in `rea-agents@6.5.0`):
  the importer marks an inventory `partial` whenever the import carries any
  limitation, and this host always carries the openat path-race limitation.
  Every entry was hashed, the directory fully enumerated and every
  relationship parsed and resolved, so nothing is missing from the inventory;
  the flag records a guarantee the importer cannot give on Node, and its
  practical effect here is that no file can be classified `removed`.
- **Why zero candidates were evaluated.** Read from
  `dist/domain/javascript/sourceToBundleSignals.js`: candidates are collected
  by index lookup on digest, path and basename before any scoring, and the
  extension signal is only added to candidates already collected. The rebuild
  is `mustache.mjs`, the bundle is `mustache.min.js`: different digest, path
  and basename, so no candidate was collected. Renaming the rebuild to
  `mustache.min.js` would have produced one basename-only candidate (score
  25, confidence `low`), which the tool's own rules still classify as
  `unknown` ("no mapping was forced"); it was not done.
- **What the comparison does establish.** Only that the rebuild shares no
  bytes, path or source map with the shipped bundle, which is consistent with
  it being new code. It says nothing about behavioural equivalence either way;
  that claim continues to rest on the differential test, and the record itself
  says static digest and location signals cannot establish equivalence.

### Unknowns and not checked

- No REA function-level comparison between the rebuild and the bundle was run.
  The REA route for that would be a second `analyze-javascript-application`
  over `rebuilds/mustache` followed by `compare-application-versions` (or
  `compare-javascript-export-shapes` for the export surface); it was outside
  this step's scope.
- The explanations of `partial` and of the empty candidate list are read from
  the installed 6.5.0 code, not from REA documentation.
- The `rea` MCP server was not used for these steps; the CLI returns the same
  Evidence records directly.

### Commands (as run from the repo root on the cloud image)

```bash
npx -y rea-agents@6.5.0 analyze-javascript-application "$PWD/targets/mustache-min" --json > /tmp/analysis.json
npx -y rea-agents@6.5.0 import-reference-source "$PWD/rebuilds/mustache" --json > /tmp/reference.json
node -e '
const fs = require("fs");
const reference = JSON.parse(fs.readFileSync("/tmp/reference.json", "utf8"));
const application = JSON.parse(fs.readFileSync("/tmp/analysis.json", "utf8"));
fs.writeFileSync("/tmp/compare-input.json", JSON.stringify({ reference, application }));
'
npx -y rea-agents@6.5.0 compare-source-to-bundle /tmp/compare-input.json --json > /tmp/compare.json
node --test rebuilds/mustache/test/differential.test.mjs
```

(The first run built the input with the same code saved as a script outside
the repo; the inline form above was verified to produce a byte-identical
input and the identical comparison record.)

/**
 * Differential tests: the rebuilt engine must behave exactly like the shipped
 * artifact `targets/mustache-min/mustache.min.js` — same output, same parse
 * tokens, same errors — on a curated corpus and on thousands of generated
 * templates.
 *
 *   node --test rebuilds/mustache/test/
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import path from "node:path";
import rebuilt from "../mustache.mjs";

const require = createRequire(import.meta.url);
const here = path.dirname(fileURLToPath(import.meta.url));
const original = require(path.resolve(here, "../../../targets/mustache-min/mustache.min.js"));

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

/** Run `fn` and capture either its value or its error as plain data. */
function outcome(fn) {
  try {
    return { ok: true, value: fn() };
  } catch (e) {
    // V8 embeds the source text of the failing expression in TypeError
    // messages ("(tags||mustache.tags).join is not a function"), so whitespace
    // differences between minified and readable code are not behaviour.
    const message = e instanceof TypeError ? e.message.replace(/\s+/g, "") : e.message;
    return { ok: false, error: `${e.constructor.name}: ${message}` };
  }
}

function renderWith(impl, c) {
  const view = typeof c.view === "function" ? c.view() : c.view;
  return outcome(() => impl.render(c.template, view, c.partials, c.config));
}

function parseWith(impl, template, tags) {
  return outcome(() => impl.parse(template, tags));
}

function assertSameBehaviour(c, label = c.name) {
  const a = renderWith(original, c);
  const b = renderWith(rebuilt, c);
  assert.deepEqual(b, a, `render mismatch: ${label}\ntemplate=${JSON.stringify(c.template)}`);
  if (typeof c.template === "string") {
    const tags = Array.isArray(c.config) ? c.config : c.config && c.config.tags;
    const pa = parseWith(original, c.template, tags);
    const pb = parseWith(rebuilt, c.template, tags);
    assert.deepEqual(pb, pa, `parse mismatch: ${label}\ntemplate=${JSON.stringify(c.template)}`);
  }
  return a;
}

// ---------------------------------------------------------------------------
// curated corpus
// ---------------------------------------------------------------------------

const bold = () => (text, render) => "<b>" + render(text) + "</b>";
const specials = "& < > \" ' / ` =";

const cases = [
  { name: "plain text", template: "Hello, World!\n", view: {} },
  { name: "variable", template: "Hello, {{name}}!", view: { name: "Ada" } },
  { name: "variable with inner spaces", template: "[{{ name }}]", view: { name: "Ada" } },
  { name: "missing variable", template: "[{{nope}}]", view: {} },
  { name: "escaping", template: "{{v}}", view: { v: specials } },
  { name: "triple mustache", template: "{{{v}}}", view: { v: specials } },
  { name: "triple with spaces", template: "{{{ v }}}", view: { v: "<x>" } },
  { name: "ampersand", template: "{{&v}}", view: { v: specials } },
  { name: "number is not escaped", template: "{{n}}|{{{n}}}|{{z}}", view: { n: 5, z: 0 } },
  { name: "custom escape receives numbers", template: "{{n}}|{{s}}", view: { n: 5, s: "<" }, config: { escape: (s) => `[${s}]` } },
  { name: "dotted names", template: "{{a.b.c}}|{{a.b}}|{{a.x.y}}", view: { a: { b: { c: "deep" } } } },
  { name: "primitive own property", template: "{{s.length}}|{{n.length}}", view: { s: "abc", n: 7 } },
  { name: "implicit iterator", template: "{{#list}}{{.}} {{/list}}", view: { list: [1, "two", 3.5] } },
  { name: "list of objects", template: "{{#people}}{{name}},{{/people}}", view: { people: [{ name: "a" }, { name: "b" }] } },
  { name: "object section", template: "{{#obj}}{{x}}-{{y}}{{/obj}}", view: { obj: { x: 1, y: 2 } } },
  { name: "string section", template: "{{#s}}[{{.}}]{{/s}}", view: { s: "str" } },
  { name: "number section", template: "{{#n}}[{{.}}]{{/n}}", view: { n: 42 } },
  { name: "zero section", template: "{{#n}}shown{{/n}}|{{^n}}hidden{{/n}}", view: { n: 0 } },
  { name: "true section", template: "{{#t}}yes{{/t}}{{^t}}no{{/t}}", view: { t: true } },
  { name: "false section", template: "{{#f}}yes{{/f}}{{^f}}no{{/f}}", view: { f: false } },
  { name: "null section", template: "{{#x}}yes{{/x}}{{^x}}no{{/x}}", view: { x: null } },
  { name: "missing section", template: "{{#x}}yes{{/x}}{{^x}}no{{/x}}", view: {} },
  { name: "empty list", template: "{{#l}}yes{{/l}}{{^l}}no{{/l}}", view: { l: [] } },
  { name: "nested context fallback", template: "{{#a}}{{#b}}{{x}}{{y}}{{/b}}{{/a}}", view: { x: "outer", a: { y: "mid", b: { z: 1 } } } },
  { name: "nested lists", template: "{{#rows}}{{#.}}{{.}}{{/.}};{{/rows}}", view: { rows: [[1, 2], [3]] } },
  { name: "section lambda", template: "{{#bold}}Hi {{name}}{{/bold}}", view: { name: "Ada", bold } },
  { name: "section lambda raw text", template: "{{#wrap}}{{name}} x{{/wrap}}", view: { name: "Ada", wrap: () => (text) => `<${text}>` } },
  { name: "section lambda returning null", template: "a{{#nul}}body{{/nul}}b", view: { nul: () => () => null } },
  { name: "variable lambda", template: "{{fn}}|{{{fn}}}", view: { fn: () => "x&y" } },
  { name: "lambda uses this", template: "{{greet}}", view: { name: "Ada", greet() { return "hi " + this.name; } } },
  { name: "partial map", template: "<{{>user}}>", view: { name: "Ada" }, partials: { user: "{{name}}!" } },
  { name: "partial function", template: "<{{> user }}>", view: { name: "Ada" }, partials: (n) => (n === "user" ? "[{{name}}]" : undefined) },
  { name: "missing partial", template: "<{{>nope}}>", view: {}, partials: {} },
  { name: "no partials given", template: "<{{>nope}}>", view: {} },
  { name: "standalone indented partial", template: "a\n  {{>p}}\nb\n", view: { v: "V" }, partials: { p: "x{{v}}\ny\n" } },
  { name: "tab-indented partial", template: "\t{{>p}}\n", view: {}, partials: { p: "l1\nl2\n" } },
  { name: "inline partial after text", template: "text {{>p}} more\n", view: {}, partials: { p: "l1\nl2\n" } },
  { name: "partial inherits context", template: "{{#items}}{{>row}}{{/items}}", view: { items: [{ n: 1 }, { n: 2 }], sep: "," }, partials: { row: "{{n}}{{sep}}" } },
  { name: "recursive partial", template: "{{>node}}", view: { v: 1, kids: [{ v: 2, kids: [{ v: 3, kids: [] }] }, { v: 4, kids: [] }] }, partials: { node: "({{v}}{{#kids}}{{>node}}{{/kids}})" } },
  { name: "comment", template: "A{{! this is a comment }}B", view: {} },
  { name: "standalone comment line removed", template: "A\n  {{! gone }}\nB\n", view: {} },
  { name: "set delimiters inline", template: "{{=<% %>=}}<%name%> {{name}}", view: { name: "Ada" } },
  { name: "set delimiters standalone line", template: "x\n{{=| |=}}\n|name|\n", view: { name: "Ada" } },
  { name: "set delimiters inside section", template: "{{#a}}{{=<% %>=}}<%v%><%/a%>", view: { a: { v: "in" } } },
  { name: "config tags array", template: "<%name%> {{name}}", view: { name: "Ada" }, config: ["<%", "%>"] },
  { name: "config tags object", template: "[[name]]", view: { name: "Ada" }, config: { tags: ["[[", "]]"] } },
  { name: "tags with regex characters", template: "{{=<[ ]>=}}<[name]>", view: { name: "Ada" } },
  { name: "standalone section lines", template: "begin\n  {{#a}}\n  x\n  {{/a}}\nend\n", view: { a: true } },
  { name: "standalone inverted lines", template: "begin\n{{^a}}\nx\n{{/a}}\nend\n", view: { a: false } },
  { name: "section tag with text on line is kept", template: "  {{#a}} x\n  {{/a}}\n", view: { a: true } },
  { name: "crlf line endings", template: "a\r\n{{#b}}\r\nx\r\n{{/b}}\r\nc\r\n", view: { b: true } },
  { name: "indentation with mixed whitespace", template: " \t {{#a}}\n\t{{.}}\n {{/a}}\n", view: { a: "v" } },
  { name: "unicode", template: "“{{v}}” — ünïcødé {{#l}}✓{{/l}}", view: { v: "ß", l: [1, 2] } },
  { name: "view is array", template: "{{#.}}{{.}}{{/.}}", view: [1, 2, 3] },
  { name: "view is string", template: "{{.}}|{{#.}}y{{/.}}", view: "str" },
  { name: "view is number", template: "{{.}}", view: 3 },
  { name: "view undefined", template: "static", view: undefined },
  { name: "error: unclosed tag", template: "hello {{name", view: {} },
  { name: "error: unclosed section", template: "{{#a}}x", view: {} },
  { name: "error: unopened section", template: "x{{/a}}", view: {} },
  { name: "error: mismatched section", template: "{{#a}}{{/b}}", view: {} },
  { name: "error: invalid delimiters", template: "{{=<% =}}", view: {} },
  { name: "error: invalid config tags string", template: "x", view: {}, config: { tags: "<% %>" } },
  { name: "error: template is a number", template: 42, view: {} },
  { name: "error: template is an array", template: ["a"], view: {} },
  { name: "error: null view with variable", template: "{{x}}", view: null },
  { name: "error: null view with dotted name", template: "{{x.y}}", view: null },
];

test("curated corpus: identical render output, parse tokens and errors", () => {
  let rendered = 0;
  let threw = 0;
  for (const c of cases) {
    const a = assertSameBehaviour(c);
    a.ok ? rendered++ : threw++;
  }
  assert.ok(rendered >= 50 && threw >= 8, `corpus sanity: rendered=${rendered} threw=${threw}`);
});

test("escape function and exports match", () => {
  assert.equal(rebuilt.escape(specials), original.escape(specials));
  for (const key of ["name", "version", "tags"]) assert.deepEqual(rebuilt[key], original[key]);
  for (const key of ["render", "parse", "clearCache", "escape", "Scanner", "Context", "Writer"]) {
    assert.equal(typeof rebuilt[key], typeof original[key], key);
  }
});

test("template cache: same keys, can be replaced and disabled", () => {
  const made = () => ({ store: {}, set(k, v) { this.store[k] = v; }, get(k) { return this.store[k]; }, clear() { this.store = {}; } });
  const cacheA = made();
  const cacheB = made();
  original.templateCache = cacheA;
  rebuilt.templateCache = cacheB;
  try {
    for (const impl of [original, rebuilt]) {
      impl.render("{{a}}", { a: 1 });
      impl.render("{{a}}", { a: 1 }, undefined, ["<%", "%>"]);
    }
    assert.deepEqual(Object.keys(cacheB.store), Object.keys(cacheA.store));
    assert.deepEqual(cacheB.store, cacheA.store);
    original.templateCache = undefined;
    rebuilt.templateCache = undefined;
    assert.equal(rebuilt.render("{{a}}", { a: "no cache" }), original.render("{{a}}", { a: "no cache" }));
  } finally {
    original.templateCache = made();
    rebuilt.templateCache = made();
  }
  original.clearCache();
  rebuilt.clearCache();
});

// ---------------------------------------------------------------------------
// generated templates (deterministic fuzz)
// ---------------------------------------------------------------------------

function makeRng(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const pick = (rng, arr) => arr[Math.floor(rng() * arr.length)];

const KEYS = ["a", "b.c", "n", "zero", "list", "obj", "empty", "t", "f", "nul", "str", "fn", "missing", ".", "s.length"];
const SECTION_KEYS = ["a", "list", "obj", "empty", "t", "f", "nul", "lam", "str", "n", "zero", "missing", "."];
const TEXT = ["Hello", " ", "  ", "\n", "\n  ", "x", "<b>&</b>", "\t", "end\n", "a=b", "“ü”", "\r\n", " \n"];
const DELIMS = [["<%", "%>"], ["[[", "]]"], ["{{", "}}"], ["<<", ">>"], ["|", "|"]];

function genTemplate(rng, depth, state) {
  let out = "";
  const n = 1 + Math.floor(rng() * 6);
  for (let i = 0; i < n; i++) {
    const r = rng();
    const [o, c] = state.tags;
    if (r < 0.3) out += pick(rng, TEXT);
    else if (r < 0.45) out += `${o}${pick(rng, KEYS)}${c}`;
    else if (r < 0.52) out += `${o}{${pick(rng, KEYS)}}${c}`;
    else if (r < 0.58) out += `${o}& ${pick(rng, KEYS)}${c}`;
    else if (r < 0.63) out += `${o}! comment ${c}`;
    else if (r < 0.7) out += `${o}>${pick(rng, ["p1", "p2", "p3", "nope"])}${c}`;
    else if (r < 0.86 && depth < 3) {
      const k = pick(rng, SECTION_KEYS);
      const sigil = rng() < 0.75 ? "#" : "^";
      out += `${o}${sigil}${k}${c}` + genTemplate(rng, depth + 1, state);
      out += `${state.tags[0]}/${k}${state.tags[1]}`; // delimiters may have changed inside
    } else if (r < 0.92) {
      const nt = pick(rng, DELIMS);
      out += `${o}=${nt[0]} ${nt[1]}=${c}`;
      state.tags = nt;
    } else if (r < 0.96) out += pick(rng, ["{{", "}}", "{{#", "{{/x}}", "{{=a=}}"]); // deliberately broken
    else out += "\n";
  }
  return out;
}

const fuzzView = () => ({
  a: 'A&<>"',
  b: { c: "bc" },
  n: 7,
  zero: 0,
  list: [1, 2, { a: "x", b: { c: "inner" } }],
  obj: { a: "oa", b: { c: "nested" } },
  empty: [],
  t: true,
  f: false,
  nul: null,
  str: "string",
  s: "abc",
  lam: () => (text, render) => "[" + render(text) + "]",
  fn: () => "fnval",
});

const fuzzPartials = {
  p1: "P1 {{a}}",
  p2: "line1\n  {{b.c}}\nline3\n",
  p3: "{{#list}}{{.}},{{/list}}",
};

test("generated templates: 3000 cases agree (output, tokens and errors)", () => {
  const rng = makeRng(20261015);
  let rendered = 0;
  let threw = 0;
  for (let i = 0; i < 3000; i++) {
    const template = genTemplate(rng, 0, { tags: ["{{", "}}"] });
    const c = { template, view: fuzzView, partials: fuzzPartials };
    const a = assertSameBehaviour(c, `fuzz #${i}`);
    a.ok ? rendered++ : threw++;
  }
  assert.ok(rendered > 1000, `fuzz sanity: rendered=${rendered} threw=${threw}`);
  assert.ok(threw > 100, `fuzz sanity: expected some error cases, threw=${threw}`);
});

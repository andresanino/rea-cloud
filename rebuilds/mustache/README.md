# rebuilds/mustache

A readable reconstruction of the template engine shipped as
[`targets/mustache-min/mustache.min.js`](../../targets/mustache-min/mustache.min.js)
(mustache 4.2.0, MIT), produced from REA's static Evidence over that minified
artifact. The investigation and its evidence trail are in
[`reports/mustache-min-2026-10-15.md`](../../reports/mustache-min-2026-10-15.md).

- `mustache.mjs` — the rebuild: ES module, classes (`Scanner`, `Context`,
  `Writer`), documented parser and renderer, same public API as the artifact.
- `test/differential.test.mjs` — proof of equivalence: every input is run
  through the shipped artifact *and* the rebuild, and output, `parse()` tokens
  and thrown errors must match. 67 curated cases (10 of them error cases) plus
  3,000 deterministically generated templates.

```bash
node --test rebuilds/mustache/test/differential.test.mjs
```

Usage is the same as mustache.js:

```js
import mustache from "./rebuilds/mustache/mustache.mjs";
mustache.render("Hello {{name}}!", { name: "World" }); // "Hello World!"
```

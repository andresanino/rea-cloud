# mustache.min.js (mustache 4.2.0)

- **Origin:** npm package `mustache@4.2.0`, file `package/mustache.min.js` from
  the registry tarball (`npm pack mustache@4.2.0`, 2026-10-15). License: MIT.
- **Identity:** 11,790 bytes, SHA-256
  `d7fd0603512461e8edbd81686bead2ab82df3389b9cca235dd9d5b408848e02a`.
- **Rule for this exercise:** only this minified artifact is analysed. The
  package's unminified `mustache.js` was deliberately not copied here and not
  read; it is not needed, because the minified build itself is the oracle for
  differential tests.

## Questions to answer

1. What public API does the artifact expose, and what does each entry point do?
2. How are templates tokenised and parsed (tag types, delimiters, standalone
   whitespace rules, nesting)?
3. How is a parsed template rendered (context lookup, sections, inverted
   sections, partials, escaping, lambdas)?
4. Can a clean, readable implementation be rebuilt from that evidence that is
   behaviourally identical on a broad set of templates?

/**
 * mustache (rebuilt) — a readable reconstruction of the template engine
 * shipped as `targets/mustache-min/mustache.min.js` (mustache 4.2.0, MIT).
 *
 * It was written from REA's static Evidence over the minified artifact
 * (Evidence ev_6aa2295d0c267f44871567f9870fc659a82f30ec36616bb7b5e2abdd136409dd:
 * 47 functions with source ranges, bindings, the entity map and the tag
 * regexes) plus a read of the artifact itself. See
 * reports/mustache-min-2026-10-15.md for the evidence trail.
 *
 * Token shapes, lookup rules, whitespace handling and error messages are kept
 * identical to the artifact on purpose: test/differential.test.mjs proves
 * equivalence by running the same inputs through both implementations.
 */

// ---------------------------------------------------------------------------
// Small helpers (artifact: isArray/isFunction/typeStr/escapeRegExp/hasProperty/
// primitiveHasOwnProperty/testRegExp/isWhitespace at columns 312–1061)
// ---------------------------------------------------------------------------

const isArray = Array.isArray;

function isFunction(value) {
  return typeof value === "function";
}

/** "array" for arrays, otherwise `typeof`; used only in the render() type error. */
function typeStr(value) {
  return isArray(value) ? "array" : typeof value;
}

function escapeRegExp(string) {
  return string.replace(/[\-\[\]{}()*+?.,\\\^$|#\s]/g, "\\$&");
}

/** `name in obj` for non-null objects only. */
function hasProperty(obj, propName) {
  return obj != null && typeof obj === "object" && propName in obj;
}

/** Own-property check for primitives (e.g. "abc".length) — never for objects. */
function primitiveHasOwnProperty(primitive, propName) {
  return (
    primitive != null &&
    typeof primitive !== "object" &&
    primitive.hasOwnProperty &&
    primitive.hasOwnProperty(propName)
  );
}

const nonSpaceRe = /\S/;

function isWhitespace(string) {
  return !nonSpaceRe.test(string);
}

// ---------------------------------------------------------------------------
// HTML escaping (artifact: entityMap literals + escapeHtml at 1175–1296)
// ---------------------------------------------------------------------------

const entityMap = {
  "&": "&amp;",
  "<": "&lt;",
  ">": "&gt;",
  '"': "&quot;",
  "'": "&#39;",
  "/": "&#x2F;",
  "`": "&#x60;",
  "=": "&#x3D;",
};

export function escapeHtml(string) {
  return String(string).replace(/[&<>"'`=\/]/g, (s) => entityMap[s]);
}

// ---------------------------------------------------------------------------
// Scanner — a cursor over the template string (artifact: 4649–5274)
// ---------------------------------------------------------------------------

export class Scanner {
  constructor(string) {
    this.string = string;
    this.tail = string;
    this.pos = 0;
  }

  /** True once the whole string has been consumed. */
  eos() {
    return this.tail === "";
  }

  /** Consume `re` if it matches at the current position; return the match or "". */
  scan(re) {
    const match = this.tail.match(re);
    if (!match || match.index !== 0) return "";
    const string = match[0];
    this.tail = this.tail.substring(string.length);
    this.pos += string.length;
    return string;
  }

  /** Consume everything up to (not including) the first match of `re`. */
  scanUntil(re) {
    const index = this.tail.search(re);
    let match;
    switch (index) {
      case -1:
        match = this.tail;
        this.tail = "";
        break;
      case 0:
        match = "";
        break;
      default:
        match = this.tail.substring(0, index);
        this.tail = this.tail.substring(index);
    }
    this.pos += match.length;
    return match;
  }
}

// ---------------------------------------------------------------------------
// Context — the view stack used for name lookup (artifact: 5275–6220)
// ---------------------------------------------------------------------------

export class Context {
  constructor(view, parentContext) {
    this.view = view;
    this.cache = { ".": this.view };
    this.parent = parentContext;
  }

  push(view) {
    return new Context(view, this);
  }

  /**
   * Resolve `name` against this context, then its parents. Dotted names walk
   * into the view; a hit is only declared when the final segment exists as a
   * property (`in`) or as an own property of a primitive. Results are cached
   * per context, and function values are invoked with the view as `this`.
   */
  lookup(name) {
    const cache = this.cache;
    let value;
    if (cache.hasOwnProperty(name)) {
      value = cache[name];
    } else {
      let context = this;
      let intermediateValue;
      let names;
      let index;
      let lookupHit = false;
      while (context) {
        if (name.indexOf(".") > 0) {
          intermediateValue = context.view;
          names = name.split(".");
          index = 0;
          while (intermediateValue != null && index < names.length) {
            if (index === names.length - 1) {
              lookupHit =
                hasProperty(intermediateValue, names[index]) ||
                primitiveHasOwnProperty(intermediateValue, names[index]);
            }
            intermediateValue = intermediateValue[names[index++]];
          }
        } else {
          intermediateValue = context.view[name];
          lookupHit = hasProperty(context.view, name);
        }
        if (lookupHit) {
          value = intermediateValue;
          break;
        }
        context = context.parent;
      }
      cache[name] = value;
    }
    if (isFunction(value)) value = value.call(this.view);
    return value;
  }
}

// ---------------------------------------------------------------------------
// Parser (artifact: parseTemplate 1403–3863, squashTokens, nestTokens)
//
// Token shapes, kept identical to the artifact so parse() output matches:
//   ["text", chars, start, end]
//   ["name" | "&", key, start, end]            ("{{{x}}}" is folded into "&")
//   ["#" | "^", key, start, end, children, closeIndex]
//   [">", key, start, end, indentation, tagIndex, lineHasNonSpace]
//   ["!", comment, start, end]   ["=", "<% %>", start, end]
// ---------------------------------------------------------------------------

const whiteRe = /\s*/;
const spaceRe = /\s+/;
const equalsRe = /\s*=/;
const curlyRe = /\s*\}/;
const tagRe = /#|\^|\/|>|\{|&|=|!/;

function parseTemplate(template, tags) {
  if (!template) return [];

  let lineHasNonSpace = false;
  const sections = []; // open section tokens, for nesting checks
  const tokens = []; // flat token stream, one "text" token per character
  let spaces = []; // indexes of whitespace text tokens on the current line
  let hasTag = false; // did the current line contain a tag?
  let nonSpace = false; // did it contain non-whitespace text (or a value tag)?
  let indentation = ""; // leading whitespace of the current line (tabs kept)
  let tagIndex = 0; // position of the next tag on the current line

  // Standalone-line rule: a line holding only whitespace and non-value tags
  // is removed entirely, whitespace included.
  function stripSpace() {
    if (hasTag && !nonSpace) {
      while (spaces.length) delete tokens[spaces.pop()];
    } else {
      spaces = [];
    }
    hasTag = false;
    nonSpace = false;
  }

  let openingTagRe;
  let closingTagRe;
  let closingCurlyRe;

  function compileTags(tagsToCompile) {
    if (typeof tagsToCompile === "string") tagsToCompile = tagsToCompile.split(spaceRe, 2);
    if (!isArray(tagsToCompile) || tagsToCompile.length !== 2) {
      throw new Error("Invalid tags: " + tagsToCompile);
    }
    openingTagRe = new RegExp(escapeRegExp(tagsToCompile[0]) + "\\s*");
    closingTagRe = new RegExp("\\s*" + escapeRegExp(tagsToCompile[1]));
    closingCurlyRe = new RegExp("\\s*" + escapeRegExp("}" + tagsToCompile[1]));
  }

  compileTags(tags || mustache.tags);

  const scanner = new Scanner(template);
  let start;
  let type;
  let value;
  let chr;
  let token;
  let openSection;

  while (!scanner.eos()) {
    start = scanner.pos;

    // Literal text up to the next opening tag, one token per character so
    // stripSpace() can later delete individual whitespace characters.
    value = scanner.scanUntil(openingTagRe);
    if (value) {
      for (let i = 0, valueLength = value.length; i < valueLength; ++i) {
        chr = value.charAt(i);
        if (isWhitespace(chr)) {
          spaces.push(tokens.length);
          indentation += chr;
        } else {
          nonSpace = true;
          lineHasNonSpace = true;
          indentation += " ";
        }
        tokens.push(["text", chr, start, start + 1]);
        start += 1;
        if (chr === "\n") {
          stripSpace();
          indentation = "";
          tagIndex = 0;
          lineHasNonSpace = false;
        }
      }
    }

    if (!scanner.scan(openingTagRe)) break;
    hasTag = true;

    // Tag sigil, then its key.
    type = scanner.scan(tagRe) || "name";
    scanner.scan(whiteRe);
    if (type === "=") {
      value = scanner.scanUntil(equalsRe);
      scanner.scan(equalsRe);
      scanner.scanUntil(closingTagRe);
    } else if (type === "{") {
      value = scanner.scanUntil(closingCurlyRe);
      scanner.scan(curlyRe);
      scanner.scanUntil(closingTagRe);
      type = "&";
    } else {
      value = scanner.scanUntil(closingTagRe);
    }
    if (!scanner.scan(closingTagRe)) throw new Error("Unclosed tag at " + scanner.pos);

    if (type == ">") {
      token = [type, value, start, scanner.pos, indentation, tagIndex, lineHasNonSpace];
    } else {
      token = [type, value, start, scanner.pos];
    }
    tagIndex++;
    tokens.push(token);

    if (type === "#" || type === "^") {
      sections.push(token);
    } else if (type === "/") {
      openSection = sections.pop();
      if (!openSection) throw new Error('Unopened section "' + value + '" at ' + start);
      if (openSection[1] !== value) {
        throw new Error('Unclosed section "' + openSection[1] + '" at ' + start);
      }
    } else if (type === "name" || type === "{" || type === "&") {
      nonSpace = true;
    } else if (type === "=") {
      compileTags(value);
    }
  }

  stripSpace();

  openSection = sections.pop();
  if (openSection) {
    throw new Error('Unclosed section "' + openSection[1] + '" at ' + scanner.pos);
  }

  return nestTokens(squashTokens(tokens));
}

/** Merge runs of single-character "text" tokens (skipping holes left by stripSpace). */
function squashTokens(tokens) {
  const squashedTokens = [];
  let lastToken;
  for (let i = 0, numTokens = tokens.length; i < numTokens; ++i) {
    const token = tokens[i];
    if (token) {
      if (token[0] === "text" && lastToken && lastToken[0] === "text") {
        lastToken[1] += token[1];
        lastToken[3] = token[3];
      } else {
        squashedTokens.push(token);
        lastToken = token;
      }
    }
  }
  return squashedTokens;
}

/** Move the tokens between a section's open and close tags into token[4]; token[5] = close offset. */
function nestTokens(tokens) {
  const nestedTokens = [];
  let collector = nestedTokens;
  const sections = [];
  for (let i = 0, numTokens = tokens.length; i < numTokens; ++i) {
    const token = tokens[i];
    switch (token[0]) {
      case "#":
      case "^":
        collector.push(token);
        sections.push(token);
        collector = token[4] = [];
        break;
      case "/": {
        const section = sections.pop();
        section[5] = token[2];
        collector = sections.length > 0 ? sections[sections.length - 1][4] : nestedTokens;
        break;
      }
      default:
        collector.push(token);
    }
  }
  return nestedTokens;
}

// ---------------------------------------------------------------------------
// Writer — parse cache + renderer (artifact: 6221–10832)
// ---------------------------------------------------------------------------

export class Writer {
  constructor() {
    this.templateCache = {
      _cache: {},
      set(key, value) {
        this._cache[key] = value;
      },
      get(key) {
        return this._cache[key];
      },
      clear() {
        this._cache = {};
      },
    };
  }

  clearCache() {
    if (typeof this.templateCache !== "undefined") {
      this.templateCache.clear();
    }
  }

  /** Parse once per (template, tags) pair; `templateCache = undefined` disables caching. */
  parse(template, tags) {
    const cache = this.templateCache;
    const cacheKey = template + ":" + (tags || mustache.tags).join(":");
    const isCacheEnabled = typeof cache !== "undefined";
    let tokens = isCacheEnabled ? cache.get(cacheKey) : undefined;
    if (tokens == undefined) {
      tokens = parseTemplate(template, tags);
      isCacheEnabled && cache.set(cacheKey, tokens);
    }
    return tokens;
  }

  render(template, view, partials, config) {
    const tags = this.getConfigTags(config);
    const tokens = this.parse(template, tags);
    const context = view instanceof Context ? view : new Context(view, undefined);
    return this.renderTokens(tokens, context, partials, template, config);
  }

  renderTokens(tokens, context, partials, originalTemplate, config) {
    let buffer = "";
    for (let i = 0, numTokens = tokens.length; i < numTokens; ++i) {
      let value = undefined;
      const token = tokens[i];
      const symbol = token[0];
      if (symbol === "#") value = this.renderSection(token, context, partials, originalTemplate, config);
      else if (symbol === "^") value = this.renderInverted(token, context, partials, originalTemplate, config);
      else if (symbol === ">") value = this.renderPartial(token, context, partials, config);
      else if (symbol === "&") value = this.unescapedValue(token, context);
      else if (symbol === "name") value = this.escapedValue(token, context, config);
      else if (symbol === "text") value = this.rawValue(token);
      if (value !== undefined) buffer += value;
    }
    return buffer;
  }

  /**
   * {{#key}}…{{/key}}: arrays render the body once per item, objects/strings/
   * numbers once with the value pushed, functions are "lambdas" that receive
   * the raw body text and a render callback, and any other truthy value
   * renders the body in the current context.
   */
  renderSection(token, context, partials, originalTemplate, config) {
    const self = this;
    let buffer = "";
    let value = context.lookup(token[1]);

    function subRender(template) {
      return self.render(template, context, partials, config);
    }

    if (!value) return;

    if (isArray(value)) {
      for (let j = 0, valueLength = value.length; j < valueLength; ++j) {
        buffer += this.renderTokens(token[4], context.push(value[j]), partials, originalTemplate, config);
      }
    } else if (typeof value === "object" || typeof value === "string" || typeof value === "number") {
      buffer += this.renderTokens(token[4], context.push(value), partials, originalTemplate, config);
    } else if (isFunction(value)) {
      if (typeof originalTemplate !== "string") {
        throw new Error("Cannot use higher-order sections without the original template");
      }
      value = value.call(context.view, originalTemplate.slice(token[3], token[5]), subRender);
      if (value != null) buffer += value;
    } else {
      buffer += this.renderTokens(token[4], context, partials, originalTemplate, config);
    }
    return buffer;
  }

  /** {{^key}}…{{/key}} renders the body only for falsy values and empty arrays. */
  renderInverted(token, context, partials, originalTemplate, config) {
    const value = context.lookup(token[1]);
    if (!value || (isArray(value) && value.length === 0)) {
      return this.renderTokens(token[4], context, partials, originalTemplate, config);
    }
  }

  /** Re-indent every non-empty line of a standalone partial with the tag's indentation. */
  indentPartial(partial, indentation, lineHasNonSpace) {
    const filteredIndentation = indentation.replace(/[^ \t]/g, "");
    const partialByNl = partial.split("\n");
    for (let i = 0; i < partialByNl.length; i++) {
      if (partialByNl[i].length && (i > 0 || !lineHasNonSpace)) {
        partialByNl[i] = filteredIndentation + partialByNl[i];
      }
    }
    return partialByNl.join("\n");
  }

  /** {{>name}}: partials may be a map or a function of the name. */
  renderPartial(token, context, partials, config) {
    if (!partials) return;
    const tags = this.getConfigTags(config);
    const value = isFunction(partials) ? partials(token[1]) : partials[token[1]];
    if (value != null) {
      const lineHasNonSpace = token[6];
      const tagIndex = token[5];
      const indentation = token[4];
      let indentedValue = value;
      if (tagIndex == 0 && indentation) {
        indentedValue = this.indentPartial(value, indentation, lineHasNonSpace);
      }
      const tokens = this.parse(indentedValue, tags);
      return this.renderTokens(tokens, context, partials, indentedValue, config);
    }
  }

  unescapedValue(token, context) {
    const value = context.lookup(token[1]);
    if (value != null) return value;
  }

  /** Numbers skip the default escaper; a custom escaper always runs. */
  escapedValue(token, context, config) {
    const escape = this.getConfigEscape(config) || mustache.escape;
    const value = context.lookup(token[1]);
    if (value != null) {
      return typeof value === "number" && escape === mustache.escape ? String(value) : escape(value);
    }
  }

  rawValue(token) {
    return token[1];
  }

  /** `config` may be a [open, close] tags array or an options object. */
  getConfigTags(config) {
    if (isArray(config)) {
      return config;
    } else if (config && typeof config === "object") {
      return config.tags;
    } else {
      return undefined;
    }
  }

  getConfigEscape(config) {
    if (config && typeof config === "object" && !isArray(config)) {
      return config.escape;
    } else {
      return undefined;
    }
  }
}

// ---------------------------------------------------------------------------
// Public API (artifact: the `mustache` object and defaultWriter, 10850–11787)
// ---------------------------------------------------------------------------

const defaultWriter = new Writer();

const mustache = {
  name: "mustache.js",
  version: "4.2.0", // behaviour-compatible with the analysed artifact's version
  tags: ["{{", "}}"],
  clearCache: undefined,
  escape: undefined,
  parse: undefined,
  render: undefined,
  Scanner: undefined,
  Context: undefined,
  Writer: undefined,
  set templateCache(cache) {
    defaultWriter.templateCache = cache;
  },
  get templateCache() {
    return defaultWriter.templateCache;
  },
};

mustache.clearCache = function clearCache() {
  return defaultWriter.clearCache();
};

mustache.parse = function parse(template, tags) {
  return defaultWriter.parse(template, tags);
};

mustache.render = function render(template, view, partials, config) {
  if (typeof template !== "string") {
    throw new TypeError(
      'Invalid template! Template should be a "string" ' +
        'but "' +
        typeStr(template) +
        '" was given as the first ' +
        "argument for mustache#render(template, view, partials)",
    );
  }
  return defaultWriter.render(template, view, partials, config);
};

mustache.escape = escapeHtml;
mustache.Scanner = Scanner;
mustache.Context = Context;
mustache.Writer = Writer;

export default mustache;

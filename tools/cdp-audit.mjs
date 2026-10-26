// Audit theme/user.css against the live Spotify DOM.
//
// Usage: node tools/cdp-audit.mjs [path/to/user.css]
// Requires Spotify started with --remote-debugging-port=9222.
//
// For every selector in the stylesheet it reports how many live elements it
// matches. Selectors that match nothing are almost always stale: Spotify keeps
// the semantic prefix (main-*, x-*) but renames or removes whole components
// between releases. Run this after every client update.

import { readFile } from "node:fs/promises";

const cssPath = process.argv[2] || "theme/user.css";

/** Extremely small CSS reader: enough for a hand-written stylesheet. */
function extractSelectors(css) {
  const clean = css.replace(/\/\*[\s\S]*?\*\//g, "");
  const rules = [];
  let depth = 0;
  let buffer = "";
  let current = "";

  for (const char of clean) {
    if (char === "{") {
      depth += 1;
      if (depth === 1) {
        current = buffer.trim();
        buffer = "";
      }
      continue;
    }
    if (char === "}") {
      depth -= 1;
      if (depth === 0) buffer = "";
      continue;
    }
    if (depth === 0) buffer += char;
    else if (depth === 1 && current.startsWith("@")) buffer += char;
    else if (depth === 1) buffer += char;
  }

  // Re-scan line by line: simpler and good enough for flat stylesheets.
  const flat = clean.replace(/@[a-z-]+[^{]*\{(?:[^{}]*\{[^{}]*\})*[^{}]*\}/gi, "");
  for (const match of flat.matchAll(/([^{}]+)\{[^{}]*\}/g)) {
    const selectorList = match[1]
      .split(",")
      .map((s) => s.trim())
      .filter(Boolean)
      .filter((s) => !s.startsWith("@"));
    for (const selector of selectorList) rules.push(selector);
  }
  return [...new Set(rules)];
}

const selectors = extractSelectors(await readFile(cssPath, "utf8"));

const targets = await (await fetch("http://127.0.0.1:9222/json")).json();
const page = targets.find(
  (t) => t.type === "page" && String(t.url).includes("xpui.app.spotify.com"),
);
if (!page) {
  console.error("No Spotify page target. Start Spotify with --remote-debugging-port=9222.");
  process.exit(1);
}

const socket = new WebSocket(page.webSocketDebuggerUrl);
let nextId = 0;
const pending = new Map();

function send(method, params) {
  return new Promise((resolve) => {
    const id = ++nextId;
    pending.set(id, resolve);
    socket.send(JSON.stringify({ id, method, params }));
  });
}

socket.addEventListener("message", (event) => {
  const message = JSON.parse(event.data);
  if (message.id && pending.has(message.id)) {
    pending.get(message.id)(message);
    pending.delete(message.id);
  }
});

/** Drop states that querySelectorAll cannot match outside a real interaction. */
function relax(selector) {
  const relaxed = selector
    .replace(/::[a-z-]+(\([^)]*\))?/gi, "")
    .replace(/:(hover|focus-visible|focus-within|focus|active|visited|disabled|checked|placeholder-shown)\b/gi, "")
    .replace(/\s+/g, " ")
    .trim();
  return relaxed || null;
}

socket.addEventListener("open", async () => {
  const expression = `
    (() => {
      const list = ${JSON.stringify(selectors.map((sel) => ({ sel, relaxed: relax(sel) })))}
        .map(({ sel, relaxed }) => ({ sel, relaxed }));
      return list.map(({ sel, relaxed }) => {
        try {
          const direct = document.querySelectorAll(sel).length;
          if (direct > 0) return { sel, n: direct };
          // Pseudo-element/pseudo-class only: cannot be counted by querySelectorAll.
          if (!relaxed) return { sel, n: 0, state: 1 };
          // Selector only matches in an interaction state (hover/focus).
          const withoutState = relaxed !== sel ? document.querySelectorAll(relaxed).length : 0;
          if (withoutState > 0) return { sel, n: 0, state: withoutState };
          return { sel, n: 0 };
        } catch (error) {
          return { sel, n: -1, error: String(error).slice(0, 80) };
        }
      });
    })()`;

  const response = await send("Runtime.evaluate", {
    expression,
    returnByValue: true,
  });

  const results = response.result?.result?.value || [];
  const alive = results.filter((r) => r.n > 0);
  const stateOnly = results.filter((r) => r.n === 0 && r.state > 0);
  const dead = results.filter((r) => r.n === 0 && !r.state);
  const invalid = results.filter((r) => r.n === -1);

  console.log(`${cssPath}: ${results.length} selectors`);
  console.log(`  live:        ${alive.length}`);
  console.log(`  state-only:  ${stateOnly.length}  (hover/focus/pseudo-element, target exists)`);
  console.log(`  dead:        ${dead.length}`);
  console.log(`  invalid:     ${invalid.length}`);

  if (dead.length) {
    console.log("\nDead selectors (match nothing in this build, on this page):");
    for (const r of dead) console.log(`  ${r.sel}`);
  }
  if (invalid.length) {
    console.log("\nInvalid selectors (browser rejected them):");
    for (const r of invalid) console.log(`  ${r.sel}  -> ${r.error}`);
  }

  const sparse = alive.filter((r) => r.n > 0 && r.n < 2);
  if (sparse.length) {
    console.log("\nSingle match (fine for shells, suspicious for repeated UI):");
    for (const r of sparse) console.log(`  ${r.n}x  ${r.sel}`);
  }

  socket.close();
});

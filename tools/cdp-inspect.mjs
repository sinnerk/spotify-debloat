// Diagnostic probe for a Spotify client started with --remote-debugging-port=9222.
// Usage: node tools/cdp-inspect.mjs
// It only reads the DOM; it never modifies the client.

const targets = await (await fetch("http://127.0.0.1:9222/json")).json();
const page = targets.find((t) => t.type === "page" && String(t.url).includes("xpui.app.spotify.com"));
if (!page) {
  console.error("No Spotify page target found. Start Spotify with --remote-debugging-port=9222.");
  process.exit(1);
}

const socket = new WebSocket(page.webSocketDebuggerUrl);
const pending = new Map();
let nextId = 0;

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

const json = (value) => `JSON.stringify(${value})`;

const probes = [
  ["data-lean", `document.documentElement.getAttribute("data-lean")`],
  ["lean-api", json(`window.Lean ? { version: window.Lean.version, enabled: window.Lean.enabled } : null`)],
  ["lean-button", `!!document.getElementById("lean-topbar-button")`],

  ["layout-roots", json(`[...document.querySelectorAll("body > *")].map((e) => ({
    tag: e.tagName, id: e.id, cls: String(e.className).slice(0, 100)
  }))`)],
  ["root-classes", json(`[...document.querySelectorAll('[class*="Root__"]')].slice(0, 24).map((e) => ({
    tag: e.tagName, id: e.id, cls: String(e.className).slice(0, 100)
  }))`)],
  ["main-containers", json(`[...document.querySelectorAll('[class*="main-view"], [class*="main-grid"], [id="main"]')].slice(0, 12).map((e) => ({
    tag: e.tagName, id: e.id, cls: String(e.className).slice(0, 120), bg: getComputedStyle(e).backgroundColor
  }))`)],

  ["lean-button-parents", json(`(() => {
    let e = document.getElementById("lean-topbar-button"); const out = [];
    while (e && out.length < 9) { out.push({ tag: e.tagName, id: e.id, cls: String(e.className).slice(0, 110) }); e = e.parentElement; }
    return out;
  })()`)],

  ["sidebar", json(`(() => {
    const el = document.querySelector('#Desktop_LeftSidebar_Id') || document.querySelector('.Root__nav-bar');
    if (!el) return null;
    return {
      tag: el.tagName, id: el.id, cls: String(el.className).slice(0, 120),
      links: [...el.querySelectorAll('a')].map((a) => ({ href: a.getAttribute('href'), text: (a.innerText || '').trim().slice(0, 28), display: getComputedStyle(a).display })),
      episodes: !!el.querySelector('.main-yourEpisodesButton-yourEpisodesButton'),
    };
  })()`)],
  ["main-bg", `(() => {
    const el = document.querySelector('.Root__main-view') || document.querySelector('#main') || document.querySelector('.main-view-container');
    return el ? { cls: String(el.className).slice(0, 120), bg: getComputedStyle(el).backgroundColor } : null;
  })()`],
  ["font", `getComputedStyle(document.body).fontFamily`],
  ["theme-radius", `getComputedStyle(document.documentElement).getPropertyValue("--lean-radius")`],

  ["home-shelves", json(`[...document.querySelectorAll('[data-testid="component-shelf"]')].map((s) => ({
    label: s.getAttribute('aria-label'), title: s.querySelector('h2')?.innerText || '',
    display: getComputedStyle(s).display,
    links: [...s.querySelectorAll('a')].map((a) => a.getAttribute('href')).slice(0, 6),
  }))`)],
  ["upgrade-download", json(`[...document.querySelectorAll('[data-testid="upgrade-button"], [data-testid="download-button"], .main-topBar-upgradeButton')].map((e) => ({
    testid: e.dataset.testid, cls: String(e.className).slice(0, 80), display: getComputedStyle(e).display
  }))`)],
];

socket.addEventListener("open", async () => {
  for (const [name, expression] of probes) {
    const response = await send("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true });
    const value = response.result?.result?.value;
    console.log(`${name}: ${typeof value === "string" ? value : JSON.stringify(value)}`);
  }
  socket.close();
});

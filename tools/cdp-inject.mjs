// Hot-load theme/user.css into a running Spotify client.
//
// Usage: node tools/cdp-inject.mjs [path/to/user.css]
// Requires Spotify started with --remote-debugging-port=9222.
//
// This is a development aid: it injects a <style> element into the live page so
// you can iterate on the stylesheet without a spicetify apply + restart. The
// injected sheet disappears on navigation reload, and it is NOT how the theme
// ships -- `lean.ps1 theme` is. Run it twice with the same file to replace the
// previous injection; run it with --remove to drop it.

import { readFile } from "node:fs/promises";

const args = process.argv.slice(2);
const remove = args.includes("--remove");
const cssPath = args.find((a) => !a.startsWith("--")) || "theme/user.css";
const css = remove ? "" : await readFile(cssPath, "utf8");

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

socket.addEventListener("open", async () => {
  const expression = remove
    ? `(() => { const el = document.getElementById("lean-preview"); if (el) el.remove(); return "removed"; })()`
    : `(() => {
         let el = document.getElementById("lean-preview");
         if (!el) {
           el = document.createElement("style");
           el.id = "lean-preview";
           document.head.appendChild(el);
         }
         el.textContent = ${JSON.stringify(css)};
         return "injected " + ${JSON.stringify(css.length)} + " bytes";
       })()`;

  const response = await send("Runtime.evaluate", {
    expression,
    returnByValue: true,
  });
  console.log(response.result?.result?.value ?? JSON.stringify(response.result));
  socket.close();
});

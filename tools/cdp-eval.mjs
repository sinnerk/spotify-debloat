// Evaluate one expression inside a running Spotify client.
// Usage:
//   node tools/cdp-eval.mjs "document.title"
//   node tools/cdp-eval.mjs --file probe.js
// Requires Spotify started with --remote-debugging-port=9222.
// Read-only by design: it never writes to the page unless your expression does.

import { readFile } from "node:fs/promises";

const args = process.argv.slice(2);
let expression = "";

if (args[0] === "--file") {
  expression = await readFile(args[1], "utf8");
} else {
  expression = args.join(" ");
}

if (!expression.trim()) {
  console.error('Usage: node tools/cdp-eval.mjs "<js expression>"');
  process.exit(2);
}

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
  // Wrap so a bare object literal does not parse as a block statement.
  const wrapped = `(async () => { return (${expression}); })()`;
  const response = await send("Runtime.evaluate", {
    expression: wrapped,
    returnByValue: true,
    awaitPromise: true,
    allowUnsafeEvalBlockedByCSP: true,
  });

  if (response.result?.exceptionDetails) {
    console.error(JSON.stringify(response.result.exceptionDetails, null, 2));
    socket.close();
    process.exit(1);
  }

  const value = response.result?.result?.value;
  console.log(typeof value === "string" ? value : JSON.stringify(value, null, 2));
  socket.close();
});

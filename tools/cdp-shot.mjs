// Capture a screenshot of the running Spotify client over CDP.
//
// Usage: node tools/cdp-shot.mjs [output.png]
// Requires Spotify started with --remote-debugging-port=9222.
// Writes a PNG next to the working directory. Screenshots are for local review
// only -- they can contain your library, playlists and profile name, so keep
// them out of the repository.

import { writeFile } from "node:fs/promises";

const output = process.argv[2] || "spotify.png";

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
  // Hide the caret and freeze animations so the capture is reproducible.
  await send("Runtime.evaluate", {
    expression: `document.body.classList.add("lean-shot")`,
  });
  const response = await send("Page.captureScreenshot", { format: "png" });
  const data = response.result?.data;
  if (!data) {
    console.error(JSON.stringify(response, null, 2));
    socket.close();
    process.exit(1);
  }
  await writeFile(output, Buffer.from(data, "base64"));
  console.log(`wrote ${output}`);
  socket.close();
});

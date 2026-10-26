/*
 * spicetify-lean - lean-ui.js
 *
 * Adds a "Lean" toggle to the top bar and exposes window.Lean.
 *
 * Deliberately tiny: no polling loop that lives forever, no DOM rewriting, no
 * network calls. The button is built with plain DOM instead of
 * Spicetify.Topbar.Button because that helper renders its icon name as text on
 * Spotify 1.3.x (there is no icon font to resolve the ligature any more).
 */
(function LeanUI() {
  "use strict";

  const VERSION = "0.2.0";
  const STORAGE_KEY = "spicetify-lean:ui";
  const root = document.documentElement;
  let enabled = localStorage.getItem(STORAGE_KEY) !== "0";

  function apply() {
    root.setAttribute("data-lean", enabled ? "1" : "0");
    const button = document.getElementById("lean-topbar-button");
    if (button) {
      button.setAttribute("aria-pressed", String(enabled));
      button.title = `Lean UI ${enabled ? "on" : "off"} - click to toggle`;
    }
  }

  function notify(message) {
    try {
      Spicetify.showNotification(message, false, 2500);
    } catch (_) {
      /* the notification API is optional */
    }
  }

  window.Lean = {
    version: VERSION,
    get enabled() {
      return enabled;
    },
    setEnabled(value) {
      enabled = Boolean(value);
      localStorage.setItem(STORAGE_KEY, enabled ? "1" : "0");
      apply();
      notify(`Lean UI ${enabled ? "on" : "off"}`);
    },
    toggle() {
      this.setEnabled(!enabled);
    },
  };

  function createButton() {
    const button = document.createElement("button");
    button.type = "button";
    button.id = "lean-topbar-button";
    button.className = "lean-topbar-button";
    button.setAttribute("aria-pressed", String(enabled));
    button.title = `Lean UI ${enabled ? "on" : "off"} - click to toggle`;

    const dot = document.createElement("span");
    dot.className = "lean-topbar-dot";
    dot.setAttribute("aria-hidden", "true");

    const label = document.createElement("span");
    label.className = "lean-topbar-label";
    label.textContent = "Lean";

    button.append(dot, label);
    button.addEventListener("click", () => window.Lean.toggle());
    return button;
  }

  function mount() {
    if (document.getElementById("lean-topbar-button")) return true;
    // Right-hand cluster of the global nav: next to the avatar, next to nothing else.
    const host =
      document.querySelector(".main-globalNav-contentRight") ||
      document.querySelector(".main-actionButtons");
    if (!host) return false;
    host.insertBefore(createButton(), host.firstChild);
    return true;
  }

  apply();

  // The top bar is mounted once and survives navigation, so a short bounded
  // retry is enough; nothing keeps running afterwards.
  let attempts = 0;
  const timer = setInterval(() => {
    attempts += 1;
    if (mount() || attempts > 40) clearInterval(timer);
  }, 500);

  console.log(`[spicetify-lean] lean-ui ${VERSION} loaded (debloat ${enabled ? "on" : "off"})`);
})();

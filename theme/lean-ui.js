/*
 * spotify-debloat - lean-ui.js
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

  const VERSION = "0.2.1";
  const STORAGE_KEY = "spotify-debloat:ui";
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

  function covered(el) {
    const rect = el.getBoundingClientRect();
    if (rect.width === 0 || rect.height === 0) return true;
    const hit = document.elementFromPoint(rect.left + rect.width / 2, rect.top + rect.height / 2);
    return !hit || !(hit === el || el.contains(hit));
  }

  function mount() {
    if (document.getElementById("lean-topbar-button")) return true;
    // Right-hand cluster of the global nav.
    const host =
      document.querySelector(".main-globalNav-contentRight") ||
      document.querySelector(".main-actionButtons");
    if (!host) return false;

    const button = createButton();
    // Insert before the last control (the avatar) instead of prepending: on
    // Spotify 1.3.8 the search field is positioned over the left edge of this
    // cluster, so anything prepended there is painted underneath it.
    const last = host.lastElementChild;
    if (last) host.insertBefore(button, last);
    else host.appendChild(button);

    // If the search field still covers it, fall back to the end of the cluster.
    if (covered(button)) host.appendChild(button);
    return true;
  }

  // The nav builds its right cluster over a few frames, so re-check coverage for
  // a bounded window and move the pill out from under the search field if it
  // ends up buried. Ten checks, then the timer is gone for good.
  function guardPlacement() {
    let checks = 0;
    const timer = setInterval(() => {
      checks += 1;
      const button = document.getElementById("lean-topbar-button");
      if (button && covered(button)) {
        const host = button.parentElement;
        if (host) host.appendChild(button);
      }
      if (checks >= 10) clearInterval(timer);
    }, 500);
  }

  apply();

  // The top bar is mounted once and survives navigation, so a short bounded
  // retry is enough; nothing keeps running afterwards.
  let attempts = 0;
  const timer = setInterval(() => {
    attempts += 1;
    if (mount() || attempts > 40) {
      clearInterval(timer);
      if (document.getElementById("lean-topbar-button")) guardPlacement();
    }
  }, 500);

  console.log(`[spotify-debloat] lean-ui ${VERSION} loaded (debloat ${enabled ? "on" : "off"})`);
})();

// Cross-browser IME composition guard for Enter-to-submit inputs.
//
// Problem: pressing Enter to confirm an IME composition (e.g. selecting a
// Chinese candidate) must NOT trigger submit. Different browsers signal this
// differently:
//   - Chrome / Firefox / Edge: e.isComposing === true on the confirming Enter
//   - Older browsers: e.keyCode === 229
//   - Safari: fires compositionend ~5ms BEFORE keydown, so isComposing is
//     already false. We need a recent compositionend timestamp to suppress.
//
// Reference: https://bugs.webkit.org/show_bug.cgi?id=165004
//
// Usage:
//   IME.bindEnter(inputEl, () => submit());
//
// Or low-level for handlers that already own a keydown listener:
//   const ime = IME.track(inputEl);
//   inputEl.addEventListener("keydown", e => {
//     if (e.key === "Enter" && !ime.isComposing(e)) submit();
//   });
const IME = (() => {
  const SAFARI_GUARD_MS = 20;

  function track(inputEl) {
    let lastCompositionEnd = -Infinity;
    const onEnd = () => { lastCompositionEnd = Date.now(); };
    inputEl.addEventListener("compositionend", onEnd);

    return {
      isComposing(e) {
        if (e.isComposing || e.keyCode === 229) return true;
        return Date.now() - lastCompositionEnd <= SAFARI_GUARD_MS;
      },
      dispose() {
        inputEl.removeEventListener("compositionend", onEnd);
      }
    };
  }

  function bindEnter(inputEl, handler, options = {}) {
    const ime = track(inputEl);
    const onKey = (e) => {
      if (e.key !== "Enter") return;
      if (options.allowShift !== true && e.shiftKey) return;
      if (ime.isComposing(e)) return;
      e.preventDefault();
      handler(e);
    };
    inputEl.addEventListener("keydown", onKey);
    return () => {
      inputEl.removeEventListener("keydown", onKey);
      ime.dispose();
    };
  }

  return { track, bindEnter };
})();

// ── ApiNorm — response-shape adapter for legacy vs current endpoints ─────
//
// Some session endpoints were ported from the upstream OpenClacky API, which
// wraps a single resource in `{ session: {...} }` and uses the field name
// `id`. MBOpenClacky's backend instead returns the SessionData object
// directly (no wrapper) and uses `session_id` (matching the SessionData
// struct). This helper normalises both shapes so the rest of the UI can
// treat them as `{ id, name, ... }` and stop sprinkling `data.session`
// lookups across the codebase.
//
//   unwrapSession(raw)
//     null / undefined          → null
//     { session: {...} }        → {...session, id: session.session_id ?? session.id}
//     { session_id, name, ... } → { ...raw, id: raw.session_id ?? raw.id }
//     { id, name, ... }         → raw (already normalised, passed through)
//
// Returns null when nothing usable was provided, so callers can use the
// result directly (`const s = ApiNorm.unwrapSession(data); if (!s) return;`).
const ApiNorm = (() => {
  function _ensureId(obj) {
    if (!obj || typeof obj !== "object") return obj;
    if (obj.id == null && typeof obj.session_id === "string") {
      obj.id = obj.session_id;
    }
    return obj;
  }

  function unwrapSession(raw) {
    if (raw == null) return null;
    // Wrapper form: { session: {...} }
    if (typeof raw === "object" && raw.session && typeof raw.session === "object") {
      return _ensureId(raw.session);
    }
    // Direct SessionData / SessionInfo form
    if (typeof raw === "object" && (raw.id || raw.session_id)) {
      return _ensureId({ ...raw });
    }
    return null;
  }

  return { unwrapSession };
})();

Clacky.ApiNorm = ApiNorm;

const Tooltip = (() => {
  const GAP = 8;
  let el = null;
  let _hideTimer = null;

  function _el() {
    if (!el) el = document.getElementById("tooltip");
    return el;
  }

  function show(anchor) {
    const tip = _el();
    if (!tip) return;
    clearTimeout(_hideTimer);

    const text = anchor.getAttribute("data-tooltip");
    if (!text) return;

    const pos = anchor.getAttribute("data-tooltip-pos") || "top";
    tip.textContent = text;
    tip.setAttribute("data-pos", pos);
    tip.style.display = "block";

    const r = anchor.getBoundingClientRect();
    const tw = tip.offsetWidth;
    const th = tip.offsetHeight;

    let top, left;
    if (pos === "bottom") {
      top  = r.bottom + GAP;
      left = r.left + r.width / 2 - tw / 2;
    } else if (pos === "left") {
      top  = r.top + r.height / 2 - th / 2;
      left = r.left - tw - GAP;
    } else if (pos === "right") {
      top  = r.top + r.height / 2 - th / 2;
      left = r.right + GAP;
    } else {
      top  = r.top - th - GAP;
      left = r.left + r.width / 2 - tw / 2;
    }

    left = Math.max(6, Math.min(left, window.innerWidth  - tw - 6));
    top  = Math.max(6, Math.min(top,  window.innerHeight - th - 6));

    tip.style.left = `${left}px`;
    tip.style.top  = `${top}px`;
    requestAnimationFrame(() => tip.classList.add("visible"));
  }

  function hide() {
    const tip = _el();
    if (!tip) return;
    tip.classList.remove("visible");
    _hideTimer = setTimeout(() => { tip.style.display = "none"; }, 120);
  }

  function init() {
    document.addEventListener("mouseover", (e) => {
      const anchor = e.target.closest("[data-tooltip]");
      if (anchor) show(anchor);
    });
    document.addEventListener("mouseout", (e) => {
      const anchor = e.target.closest("[data-tooltip]");
      if (!anchor) return;
      if (!anchor.contains(e.relatedTarget)) hide();
    });
  }

  return { init, show, hide };
})();

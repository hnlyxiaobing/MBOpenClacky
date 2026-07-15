// CodeMirror 6 loader for the MBOpenClacky web UI.
//
// Calibration note (2026-07-15):
//   The legacy spec `2026-07-13_06_frontend-components.md` planned a
//   `web/js/components/code-editor.js` (CodeMirror 5/6) for the old
//   vanilla-JS front end. That front end no longer exists — the UI was
//   migrated to the `rabbita` framework (MoonBit, `web/mb/main/*_cell.mbt`).
//   This file is the calibrated equivalent: it lazy-loads CodeMirror 6 from
//   a CDN as an ES module and auto-mounts it into any element carrying the
//   `code-editor-host` class. The MoonBit side (`code_editor.mbt`) renders a
//   host <div> plus a hidden, model-bound <textarea>; edits in CodeMirror are
//   mirrored back into that textarea, so the existing Elm-style `on_change`
//   update loop stays the single source of truth. If the CDN fails to load,
//   the visible <textarea> remains as a graceful fallback.

import { EditorView, basicSetup } from "https://esm.sh/codemirror@6.0.1";
import { markdown } from "https://esm.sh/@codemirror/lang-markdown@6.3.0";
import { oneDark } from "https://esm.sh/@codemirror/theme-one-dark@6.1.2";

const registry = {};

function mountCM(host) {
  const id = host.id;
  if (!id || registry[id]) return;
  const ta = host.parentElement
    ? host.parentElement.querySelector("textarea.code-editor-ta")
    : null;
  const initial = ta ? ta.value : host.getAttribute("data-cm-value") || "";
  const view = new EditorView({
    doc: initial,
    parent: host,
    extensions: [
      basicSetup,
      markdown(),
      oneDark,
      EditorView.updateListener.of((u) => {
        if (u.docChanged && ta) {
          ta.value = u.state.doc.toString();
          ta.dispatchEvent(new Event("input", { bubbles: true }));
          ta.dispatchEvent(new Event("change", { bubbles: true }));
        }
      }),
    ],
  });
  registry[id] = view;
  // Editor is live — hide the fallback textarea (kept visible until now so
  // the field is never blank while the CDN module loads).
  if (ta) ta.style.display = "none";
}

// Push external content into an already-mounted editor (no-op if not mounted).
function setDoc(id, value) {
  const v = registry[id];
  if (!v) return;
  const cur = v.state.doc.toString();
  if (cur !== value) {
    v.dispatch({ changes: { from: 0, to: cur.length, insert: value } });
  }
}

const obs = new MutationObserver((muts) => {
  for (const m of muts) {
    m.addedNodes.forEach((n) => {
      if (n.nodeType === 1) {
        if (n.classList && n.classList.contains("code-editor-host")) mountCM(n);
        if (n.querySelectorAll) {
          n.querySelectorAll(".code-editor-host").forEach(mountCM);
        }
      }
    });
  }
  // Tear down editors whose host node was removed by a re-render.
  for (const id in registry) {
    if (!registry[id].dom.isConnected) {
      registry[id].destroy();
      delete registry[id];
    }
  }
});

obs.observe(document.body, { childList: true, subtree: true });
// Initial scan in case a host is already present at load time.
document.querySelectorAll(".code-editor-host").forEach(mountCM);

window.MBEditor = { setDoc };
window.MBEditorReady = true;

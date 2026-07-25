# Fork Patch Registry

Patches applied to the upstream openclacky web assets in this fork.
Each entry records what was changed, why, and when it should be reverted or replaced.

## Active Patches

### P3-001: Drain auth probe response body (2026-07-25, I-039)

- **Scope**: `auth.js` (`_probe`)
- **Reason**: The probe fetches `/api/sessions?limit=1` but only reads `r.ok`/`r.status`. Against this server's chunked keep-alive responses Chromium never marks an unconsumed request as finished, so the probe stayed "in flight" forever and `networkidle` was never reached on page load (orig 2.8s vs current 16.8s). The fix awaits `r.arrayBuffer()` and discards it.
- **Re-apply after upstream sync**: Yes, unless the server starts sending Content-Length framed responses.

### P3-002: Drain delete-session response body (2026-07-25, I-038)

- **Scope**: `sessions.js` (both `deleteSession` implementations)
- **Reason**: The DELETE returns 204 with no body to read; Chromium reports `net::ERR_ABORTED` for the request even though the status (204) is delivered and the deletion succeeds. Awaiting `res.text()` silences the spurious failure. Root cause is shared with P3-001 (unconsumed fetch bodies vs chunked/keep-alive framing).
- **Re-apply after upstream sync**: Yes, same condition as P3-001.

### P3-003: Add `sessions.untitled` i18n key (2026-07-25, I-037)

- **Scope**: `i18n.js` (en + zh)
- **Reason**: Upstream lacks the key; `I18n.t` returns the raw key which defeats the `|| "Untitled"` fallback in `sessions.js`. Added `sessions.untitled` ("Untitled" / "未命名会话").
- **Re-apply after upstream sync**: Yes, until upstream ships the key.

### P0-001: Brand Asset Placeholder (2026-07-21)

- **Scope**: `favicon.svg`, `icon*.svg`, `apple-touch-icon-180.png`, `logo_nav_dark.png`
- **Status**: Pending replacement - currently using upstream brand assets verbatim. Must be replaced with MBOpenClacky-specific brand SVG/PNG before any external release.
- **Action required**: Design MBOpenClacky-specific brand assets and replace before any external release.
- **Legal note**: Upstream OpenClacky brand assets must NOT ship in MBOpenClacky distributions.

## Retired Patches

### P0-002: Minimal Skeleton in Place of Full Upstream Bundle (2026-07-21 -> 2026-07-22)

- **Scope**: `index.html`, `app.js`, `app.css`
- **Reason**: Upstream assets not yet importable (legal/brand review pending). P0 ships a minimal skeleton that satisfies the first-screen rendering contract.
- **Resolution**: Full upstream asset set (87 files) imported in spec-02 (2026-07-22). Skeleton files overwritten by upstream originals.

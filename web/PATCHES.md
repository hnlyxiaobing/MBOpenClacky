# Fork Patch Registry

Patches applied to the upstream openclacky web assets in this fork.
Each entry records what was changed, why, and when it should be reverted or replaced.

## Active Patches

### P0-001: Brand Asset Placeholder (2026-07-21)

- **Scope**: `favicon.svg`, `icon*.svg`, `apple-touch-icon-180.png`, logo
- **Status**: Pending replacement — currently using inline SVG data-URI favicon, `favicon.svg` placeholder for the nav logo, and CSS text fallback.
- **Action required**: Design MBOpenClacky-specific brand SVG assets and replace before any external release.
- **Legal note**: Upstream OpenClacky brand assets must NOT ship in MBOpenClacky distributions.

### P0-002: Minimal Skeleton in Place of Full Upstream Bundle (2026-07-21)

- **Scope**: `index.html`, `app.js`, `app.css`
- **Reason**: Upstream assets not yet importable (legal/brand review pending). P0 ships a minimal skeleton that satisfies the first-screen rendering contract.
- **Action required**: Replace with full upstream asset set per `UPSTREAM_SYNC.md` procedure once available.

## Retired Patches

_(none yet)_

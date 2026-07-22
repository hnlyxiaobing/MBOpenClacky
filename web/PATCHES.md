# Fork Patch Registry

Patches applied to the upstream openclacky web assets in this fork.
Each entry records what was changed, why, and when it should be reverted or replaced.

## Active Patches

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

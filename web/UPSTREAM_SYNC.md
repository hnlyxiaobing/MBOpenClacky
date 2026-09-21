# Upstream Sync Baseline

## Source

- **Upstream repository**: `github.com/clacky-ai/openclacky` (reference only — not a build dependency; see README.md)
- **Baseline tag**: `v1.5.0`
- **Baseline commit**: `52205e1454ab101c2e642d6e212c6d6d5eb6ebcb`
- **Initial sync date**: 2026-07-21
- **Last sync date**: 2026-07-24 (fix-06: v1.4.0 → v1.5.0 sync - 87 upstream files)

## Current Status

The web frontend uses a **managed fork** approach:
- Full upstream asset set (87 files) synced to v1.5.0 on 2026-07-24 (fix-06). `index.html`, `app.js`, `app.css`, and all feature/vendor/i18n modules are upstream originals.
- `{{BRAND_NAME}}` and `{{EXT_SCRIPTS}}` placeholders in `index.html` are processed at runtime by `lib/web/template_processor.mbt` (`process_template()`).
- Brand assets (`favicon.svg`, `icon*.svg`, `apple-touch-icon-180.png`, `logo_nav_dark.png`, `favicon.ico`): **MBOpenClacky-owned designs** (2026-09-21, WP-0.1). Before replacement all six files were verified byte-identical to upstream v1.5.0 originals; they now carry the MBOpenClacky mark (P0-001 resolved, see `PATCHES.md`).
- `web/ext_ui/` (git, time-machine panels): MBOpenClacky-specific additions, excluded from upstream sync.
- `web/PATCHES.md`: P0-001 (brand assets) **resolved** 2026-09-21. P0-002 (minimal skeleton) retired.

## Sync Procedure (Execution Checklist)

Use this template for each quarterly upstream sync:

### 1. Fetch Upstream

```bash
git clone --depth 1 --branch v1.5.0 https://github.com/clacky-ai/openclacky.git /tmp/openclacky
```

### 2. Diff Verification

```bash
diff -rq /tmp/openclacky/lib/clacky/web/ ./web/ --exclude=PATCHES.md --exclude=UPSTREAM_SYNC.md
```

Record file count and notable deltas. Expected: 87 upstream files + PATCHES.md + UPSTREAM_SYNC.md = 89 total.

### 3. Selective Sync

```bash
rsync -av --delete \
  --exclude='favicon.svg' \
  --exclude='icon*.svg' \
  --exclude='apple-touch-icon-180.png' \
  --exclude='logo_nav_dark.png' \
  --exclude='favicon.ico' \
  --exclude='ext_ui/' \
  --exclude='PATCHES.md' \
  --exclude='UPSTREAM_SYNC.md' \
  /tmp/openclacky/lib/clacky/web/ ./web/
```

### 4. Re-apply Patches

Check `web/PATCHES.md` for active patches and re-apply them.

### 5. Regression Tests

```bash
moon fmt
moon check
moon test lib/web
# Run web eval scenarios:
moon run cmd -- --web-eval test/scenarios/web/
```

### 6. Record Sync

Update this file with:
- New commit hash (if baseline changed)
- New file count
- Date of sync
- Notable changes

## Conflict Resolution

| Conflict type | Policy |
|---|---|
| Brand assets (logo, favicon, icons) | **Keep MBOpenClacky placeholders**; never overwrite with upstream brand |
| Vendor libraries (katex, codemirror, etc.) | Accept upstream version; re-audit `THIRD_PARTY_LICENSES.md` |
| `index.html` structure | Merge: preserve `id="top-header"` + template placeholders (`{{BRAND_NAME}}`, `{{EXT_SCRIPTS}}`) |
| JS/CSS | Accept upstream; re-apply patches from `PATCHES.md` |

## Brand Assets

MBOpenClacky uses its own brand assets (not upstream OpenClacky brand), designed and introduced 2026-09-21 (WP-0.1):
- Mark: a chat bubble with a terminal prompt chevron `❯` + cursor, gradient `#14B8A6` (teal) → `#3B82F6` (blue).
- `favicon.svg`: 28×28 mark (gradient bubble, white prompt glyph).
- `icon.svg` / `icon-dark.svg`: 100×100 app icons (white bubble on gradient tile / gradient bubble on dark slate tile).
- `apple-touch-icon-180.png`: 180×180 raster of the app icon.
- `logo_nav_dark.png`: 87×112 transparent nav mark (same canvas as the file it replaced).
- `favicon.ico`: 16×16 raster favicon.

Fork deltas that travel with the brand replacement: `index.html` header-logo `alt`, `features/brand/view.js` default logo text/alt (now "MBOpenClacky"). All six asset files are excluded from upstream sync (see the rsync command below), so an upstream sync cannot reintroduce upstream brand assets.

**Legal note**: Upstream OpenClacky brand assets must NOT ship in MBOpenClacky distributions. Status 2026-09-21: verified absent (all six files hash-compared against upstream v1.5.0 and differ).

## Sync History

| Date | Upstream Tag | Files Changed | Notes |
|------|-------------|---------------|-------|
| 2026-07-21 | v1.4.0 | Initial import | Minimal skeleton created in-place (P0) |
| 2026-07-22 | v1.4.0 | Legacy cleanup | web-parity-05: deleted `legacy_mb/` and old SPA assets |
| 2026-07-22 | v1.4.0 | Full import (87 files) | spec-02: complete upstream asset set copied; P0-002 retired |
| 2026-07-24 | v1.5.0 | 15 files changed | fix-06: v1.4.0→v1.5.0 sync; new features: reload-header, advanced new-session options, extensions brand filter, background theme settings; ext_ui/ excluded from --delete |

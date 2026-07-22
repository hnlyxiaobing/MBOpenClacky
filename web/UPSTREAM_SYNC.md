# Upstream Sync Baseline

## Source

- **Upstream repository**: `github.com/clacky-ai/openclacky` (reference only — not a build dependency; see README.md)
- **Baseline tag**: `v1.4.0`
- **Baseline commit**: 未建立（上游资产尚未正式导入，无从考证基线提交；首次正式导入时记录 commit hash）
- **Initial sync date**: 2026-07-21
- **Last sync date**: 2026-07-22 (spec-02: full upstream asset import - 87 files)

## Current Status

The web frontend uses a **managed fork** approach:
- Full upstream asset set (87 files) imported on 2026-07-22 (spec-02). `index.html`, `app.js`, `app.css`, and all feature/vendor/i18n modules are upstream originals.
- `{{BRAND_NAME}}` and `{{EXT_SCRIPTS}}` placeholders in `index.html` are processed at runtime by `lib/web/template_processor.mbt` (`process_template()`).
- Brand assets (`favicon.svg`, `icon*.svg`, `apple-touch-icon-180.png`, `logo_nav_dark.png`): upstream originals still in place - P0-001 active, must be replaced before external release (see `PATCHES.md`).
- `web/PATCHES.md`: P0-001 (brand placeholders) remains **Active**. P0-002 (minimal skeleton) retired.

## Sync Procedure (Execution Checklist)

Use this template for each quarterly upstream sync:

### 1. Fetch Upstream

```bash
git clone --depth 1 --branch v1.4.0 https://github.com/clacky-ai/openclacky.git /tmp/openclacky
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

MBOpenClacky uses its own brand assets (not upstream OpenClacky brand):
- `favicon.svg`: MBOpenClacky monogram SVG (also used as the nav logo placeholder)
- `icon*.svg`, `apple-touch-icon-180.png`: MBOpenClacky icon SVG

**Legal note**: Upstream OpenClacky brand assets must NOT ship in MBOpenClacky distributions.

## Sync History

| Date | Upstream Tag | Files Changed | Notes |
|------|-------------|---------------|-------|
| 2026-07-21 | v1.4.0 | Initial import | Minimal skeleton created in-place (P0) |
| 2026-07-22 | v1.4.0 | Legacy cleanup | web-parity-05: deleted `legacy_mb/` and old SPA assets |
| 2026-07-22 | v1.4.0 | Full import (87 files) | spec-02: complete upstream asset set copied; P0-002 retired |

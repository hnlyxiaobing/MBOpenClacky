# Upstream Sync Baseline

## Source

- **Upstream repository**: `github.com/clacky-ai/openclacky` (reference only — not a build dependency; see README.md)
- **Baseline tag**: `v1.4.0`
- **Baseline commit**: 未建立（上游资产尚未正式导入，无从考证基线提交；首次正式导入时记录 commit hash）
- **Initial sync date**: 2026-07-21
- **Last sync date**: 2026-07-22 (web-parity-05: legacy cleanup, brand assets)

## Current Status

The web frontend uses a **managed fork** approach:
- `index.html`, `app.css`, `app.js`: minimal skeleton satisfying the first-screen rendering contract
  (`id="top-header"`, sidebar, theme toggle, i18n stub, `{{BRAND_NAME}}`/`{{EXT_SCRIPTS}}` placeholders).
- Brand assets: MBOpenClacky-specific placeholders (see Brand Assets section below).
- `web/PATCHES.md`: P0-001 (brand placeholders) and P0-002 (minimal skeleton) remain **Active**.

The full upstream asset set has **not yet been imported**. Importing the complete upstream
bundle is deferred until the legal review of brand assets and third-party vendor licenses
is completed (tracked in `web/PATCHES.md`).

## Sync Procedure (Execution Checklist)

Use this template for each quarterly upstream sync:

### 1. Fetch Upstream

```bash
git clone --depth 1 --branch v1.4.0 https://github.com/clacky-ai/openclacky.git /tmp/openclacky
```

### 2. Diff Verification

```bash
diff -rq /tmp/openclacky/lib/clacky/web/ ./web/
```

Record file count and notable deltas.

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

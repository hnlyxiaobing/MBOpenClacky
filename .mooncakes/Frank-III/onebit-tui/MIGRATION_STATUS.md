# OneBit-TUI Migration Status

## Current State (Sep 2024)

- **Old System**: 15 files in `components/` - complex, duplicated
- **New System**: 5 files in `widget/` - clean, trait-based
- **Build Status**: BROKEN (28 errors)

## Immediate Priority Actions

### 1. Fix Build Errors (URGENT)

- [ ] Fix Double::min/max errors (use proper imports)
- [ ] Fix pattern matching with | (not supported in MoonBit)
- [ ] Fix duplicate definitions
- [ ] Get to green build

### 2. Complete Core Migration

- [ ] Move rendering logic to new system
- [ ] Create proper app runner using new components
- [ ] Fix event handling in new system

### 3. Clean Up Old Code

- [ ] Remove duplicate event loops (3 of them!)
- [ ] Delete unnecessary helpers
- [ ] Consolidate into new structure

## File Status

### Keep & Migrate

- `components/view.mbt` → Already creating `view/view.mbt` ✅
- `components/render_helpers.mbt` → Move to `view/render.mbt`
- `components/layout.mbt` → Move to `view/layout.mbt`
- `components/app.mbt` → Simplify into `app/runner.mbt`

### Delete (Duplicates/Unnecessary)

- `components/event_loop.mbt` - Duplicate
- `components/simple_loop.mbt` - Duplicate
- `components/state.mbt` - Just use Ref
- `components/dsl.mbt` - Unclear purpose
- `components/view_events.mbt` - Being replaced

### Refactor as Widgets

- `components/checkbox.mbt` → `widget/checkbox.mbt`
- `components/modal.mbt` → `widget/modal.mbt`
- `components/select.mbt` → `widget/select.mbt`
- `components/table.mbt` → `widget/table.mbt`
- `components/controls.mbt` → Split into individual widgets

## Success Metrics

1. Build passes with 0 errors
2. Single event loop (not 3)
3. All widgets use Component trait
4. Demo runs with new API
5. Old components/ folder deleted

## Next Session Goals

1. Fix build errors
2. Get demo running with new API
3. Delete at least 5 old files

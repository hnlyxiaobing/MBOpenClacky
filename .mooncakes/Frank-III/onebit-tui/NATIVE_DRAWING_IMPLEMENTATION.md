# Native Drawing Implementation - OneBit-TUI

## Summary of Implementation

Successfully implemented native `draw_box` FFI integration and scissor-based overflow clipping for OneBit-TUI, achieving visual parity with upstream OpenTUI.

## Changes Made

### 1. View Enhancements (`src/view/view.mbt`)

- Added `TitleAlign` enum with `Left`, `Center`, `Right` variants
- Added `title_align` field to View struct
- Added `View::title_align()` builder method
- All changes are backward compatible (optional field defaults to `Left`)

### 2. Layout Engine Updates (`src/layout/layout_engine.mbt`)

- Replaced ASCII border rendering with native `draw_box` FFI call
- Implemented `border_chars_for()` function to map `BorderStyle` to Unicode box-drawing characters:
  - `Single`: Standard box characters (┌┐└┘─│┬┴├┤┼)
  - `Double`: Double-line box characters (╔╗╚╝═║╦╩╠╣╬)
  - `Rounded`: Rounded corner characters (╭╮╰╯─│┬┴├┤┼)
- Added proper packing of draw options into UInt bit field:
  - Bits 0-3: Border sides (all sides = 0b1111)
  - Bit 4: Fill background flag
  - Bits 5-6: Title alignment (0=left, 1=center, 2=right)
- Integrated scissor rect push/pop for overflow clipping:
  - Push scissor before rendering children when `overflow_y` is `Hidden` or `Scroll`
  - Pop scissor after rendering children

### 3. Demo Creation (`src/demo/box_demo.mbt`)

Created comprehensive demo showcasing:

- Three boxes with different title alignments (Left, Center, Right)
- Different border styles (Single, Double, Rounded)
- Background colors using `@core.rgb(r, g, b)`
- Overflow hidden test with content exceeding container height

### 4. Color Module Enhancement (`src/core/color.mbt`)

- Added `color_to_rgba()` function for extracting RGBA values
- Properly handles both RGB and RGBA color variants

## Technical Details

### FFI Integration

The implementation leverages existing FFI functions:

- `bufferDrawBoxMB()` - Draw box with Unicode characters
- `bufferPushScissorRect()` - Push clipping rectangle
- `bufferPopScissorRect()` - Pop clipping rectangle

### Border Character Mapping

```moonbit
// Unicode box-drawing characters for each style
Single:  ┌(0x250C) ┐(0x2510) └(0x2514) ┘(0x2518) ─(0x2500) │(0x2502)
Double:  ╔(0x2554) ╗(0x2557) ╚(0x255A) ╝(0x255D) ═(0x2550) ║(0x2551)
Rounded: ╭(0x256D) ╮(0x256E) ╰(0x2570) ╯(0x256F) ─(0x2500) │(0x2502)
```

### Packed Options Format

```
UInt packed options (32 bits):
[31...7][6-5][4][3-0]
         |    |   |
         |    |   +-- Border sides (top, right, bottom, left)
         |    +------ Fill background
         +----------- Title alignment (0=left, 1=center, 2=right)
```

## Benefits Achieved

1. **Visual Quality**: Native box drawing with proper Unicode characters instead of ASCII approximation
2. **Performance**: Direct FFI calls to Zig renderer, no character-by-character drawing
3. **Feature Parity**: Title alignment matches TypeScript OpenTUI
4. **Overflow Support**: Proper content clipping for scrollable containers
5. **Clean API**: Builder pattern remains consistent, no breaking changes

## Testing

Run the demo with:

```bash
cd onebit-tui
ONEBIT_SKIP_PREBUILD=1 moon build --target native
./target/native/release/build/demo/demo.native
```

The demo will display:

- Three boxes showing different title alignments
- Overflow clipping demonstration
- Various border styles and colors

## Next Steps

1. **Publishing Readiness**:
   - Update `moon.mod.json` to use published onebit-yoga version
   - Document `ONEBIT_SKIP_PREBUILD` in distribution guide
   - Add `#borrow` annotations to FFI parameters

2. **Additional Features**:
   - Implement scroll offset for `Overflow::Scroll`
   - Add horizontal overflow support
   - Support partial border sides (e.g., only top and bottom)

3. **Optimization**:
   - Cache border character arrays
   - Batch scissor operations
   - Profile and optimize hot paths

## Code Quality

- All code formatted with `moon fmt`
- Interface files updated with `moon info`
- No compilation errors
- Warnings are FFI annotation-related (to be addressed)

This implementation brings OneBit-TUI significantly closer to feature parity with upstream OpenTUI while maintaining a clean, idiomatic MoonBit API.

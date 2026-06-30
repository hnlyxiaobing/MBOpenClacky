# OneBit-TUI Next Steps

Based on upstream OpenTUI changes, here are the priority improvements to implement:

## 1. Text Wrapping Support 🔥 HIGH PRIORITY

The upstream has added comprehensive text wrapping capabilities:

- Word wrap and character wrap modes
- Virtual lines for wrapped text
- Better text buffer performance

### Implementation Plan:

- Add FFI bindings for `textBufferSetWrapWidth` and `textBufferSetWrapMode`
- Create a `TextArea` widget that supports wrapping
- Update `View::text` to support wrap options
- Example use case: Long descriptions, help text, README viewers

## 2. Bracketed Paste Support 📋 MEDIUM PRIORITY

Enable proper paste handling in terminal:

- Detect when text is pasted vs typed
- Handle multi-line paste properly in TextInput
- Prevent control sequences in pasted text from executing

### Implementation Plan:

- Add FFI for bracketed paste mode enable/disable
- Update TextInput widget to handle paste events
- Add `on_paste` callback to input widgets

## 3. TabSelect Widget Implementation 🎯 HIGH PRIORITY

Create a horizontal tab selector (like browser tabs):

```
┌──────┬──────┬──────┐
│ Tab1 │ Tab2 │ Tab3 │
└──────┴──────┴──────┘
```

### Implementation Plan:

- Create `TabSelect` widget with:
  - Horizontal layout of tabs
  - Active tab highlighting
  - Keyboard navigation (Left/Right arrows)
  - Content switching based on selection
  - Customizable tab renderer

## 4. Modal/Dialog Widget 💬 MEDIUM PRIORITY

Overlay dialogs for confirmations, forms, etc:

- Focus trap (Tab cycles within modal)
- Backdrop to dim background
- Escape to close
- Centered positioning

### Implementation Plan:

- Create `Modal` widget with:
  - Overlay rendering (high z-index concept)
  - Focus management
  - Backdrop with transparency
  - Animation support (fade in/out)

## 5. Improved Terminal Capabilities Detection 🔧 LOW PRIORITY

The upstream improved terminal detection:

- Better pixel resolution queries
- Enhanced capability detection
- Improved shutdown sequence

### Implementation Plan:

- Add FFI for `queryPixelResolution`
- Better terminal type detection
- Graceful fallbacks for limited terminals

## 6. Performance Optimizations ⚡ MEDIUM PRIORITY

Upstream improvements to consider:

- Text buffer memory optimizations
- Virtual line caching
- Better grapheme handling

### Implementation Plan:

- Profile current performance bottlenecks
- Implement lazy rendering for large lists
- Add viewport culling for off-screen elements

## 7. EditBuffer for Advanced Text Editing 📝 LOW PRIORITY

For more sophisticated text editing:

- Undo/redo support
- Selection and clipboard operations
- Syntax highlighting support
- Multi-cursor editing

### Implementation Plan:

- Port EditBuffer concept from upstream
- Create `CodeEditor` widget
- Add syntax highlighting via tree-sitter bindings

## 8. Animation System 🎬 LOW PRIORITY

Smooth transitions and animations:

- Use upstream Timeline API
- Easing functions
- Property animations (position, color, size)

### Implementation Plan:

- Study upstream Timeline implementation
- Create animation primitives
- Add to widgets (collapse/expand, fade, slide)

## Priority Order for Next Session:

1. **TabSelect Widget** - Completes our basic widget set
2. **Text Wrapping** - Major usability improvement
3. **Modal/Dialog** - Common UI pattern needed
4. **Bracketed Paste** - Better input handling

## Quick Wins:

- Add `textBufferSetWrapWidth` FFI binding
- Create simple TabSelect widget
- Fix absolute positioning in layout engine
- Add more examples to showcase widgets

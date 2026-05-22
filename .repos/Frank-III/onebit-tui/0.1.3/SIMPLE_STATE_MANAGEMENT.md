# OneBit-TUI Simple State Management

## Overview

We've removed the complex reactive system (signals, computed, effects) in favor of a much simpler approach using just `Ref[T]` for state management. This makes the codebase easier to understand and maintain.

## Philosophy

1. **Just use Refs** - MoonBit's built-in `Ref[T]` is all you need for mutable state
2. **Rebuild on change** - When state changes, rebuild the UI view
3. **Compute inline** - Derived values are just computed on-the-fly during render
4. **No magic** - Everything is explicit and easy to understand

## Basic Usage

```moonbit
fn main {
  // Simple mutable state
  let count = Ref::new(0)
  let name = Ref::new("World")

  // View function - rebuilds when called
  let app_view = fn() -> View {
    // Compute derived values inline - it's cheap!
    let doubled = count.val * 2
    let message = "Hello \{name.val}, count is \{count.val}"

    View::column([
      View::text(message),
      View::text("Doubled: \{doubled}"),

      // Conditional rendering - just use if/else
      if count.val > 10 {
        View::text("Count is high!").color(Color::Red)
      } else {
        View::empty()
      },

      View::button("Increment").on_click(fn() {
        count.val = count.val + 1
        request_rerender() // Tell the UI to redraw
      })
    ])
  }

  // Run the app
  run_simple_loop(app, app_view)
}
```

## Key Concepts

### State is just Refs

```moonbit
let count = Ref::new(0)
let items = Ref::new([])
let user = Ref::new(User::default())
```

### Derived values are just computations

```moonbit
// Instead of reactive computed values, just compute inline
let doubled = count.val * 2
let total = items.val.length()
let greeting = "Hello, \{user.val.name}!"
```

### Updates trigger redraws

```moonbit
button.on_click(fn() {
  count.val = count.val + 1
  request_rerender() // Marks UI as needing redraw
})
```

### The render loop

```moonbit
while running {
  if needs_rerender {
    let ui = view_fn()  // Rebuild UI with current state
    render(ui)
  }
  handle_events()
  sleep(frame_time)
}
```

## Why This Approach?

1. **Simplicity** - No complex dependency tracking or effect scheduling
2. **Predictability** - State changes are explicit and immediate
3. **Performance** - Terminal UIs are fast enough that rebuilding is cheap
4. **Debuggability** - Easy to understand what's happening

## Performance Considerations

You might think "rebuilding every frame is slow", but:

- **Terminal is the bottleneck** - Terminals can only update so fast
- **View construction is cheap** - Just creating structs
- **Yoga caches layout** - Layout calculations are optimized
- **Computations are trivial** - `count * 2` takes nanoseconds

For expensive computations (rare in UIs), you can manually cache:

```moonbit
let cached_result = Ref::new(None)
let last_input = Ref::new("")

fn get_filtered(items: Array[Item], query: String) -> Array[Item] {
  if query == last_input.val {
    match cached_result.val {
      Some(result) => return result
      None => ()
    }
  }

  let result = expensive_filter(items, query)
  cached_result.val = Some(result)
  last_input.val = query
  result
}
```

## Migration from Reactive System

| Old (Reactive)                     | New (Simple)                           |
| ---------------------------------- | -------------------------------------- |
| `@reactive.signal(0)`              | `Ref::new(0)`                          |
| `@reactive.computed(fn() { ... })` | Just compute inline: `let value = ...` |
| `@reactive.effect(fn() { ... })`   | Not needed - rebuild on change         |
| `signal.get()`                     | `ref.val`                              |
| `signal.set(value)`                | `ref.val = value; request_rerender()`  |
| `@reactive.flush()`                | `request_rerender()`                   |

## Best Practices

1. **Keep state minimal** - Only store what can't be computed
2. **Compute derived values inline** - Don't cache unless needed
3. **Use conditional rendering** - Just use if/else expressions
4. **Request rerender after state changes** - Ensure UI updates

## Example: Counter with All Features

See `/src/demo/simple_counter/main.mbt` for a complete example showing:

- Multiple state values
- Derived computations
- Conditional rendering
- Event handling
- Dynamic lists

This approach has proven successful in immediate mode GUIs like Dear ImGui and egui, and works perfectly for terminal UIs!

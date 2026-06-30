# State-Based Rendering Optimization Design

## Problem Statement

The current OneBit-TUI rendering approach rebuilds the entire view tree on every frame, which is inefficient compared to TypeScript OpenTUI's optimized buffer diffing. Additionally, when widgets handle their own events and modify internal state, the event loop doesn't know about these changes, making automatic dirty tracking difficult.

## The Synchronization Challenge

From previous signal-based approaches, we've learned about critical synchronization issues:

1. **Diamond Dependencies**: When A → B and A → C, then B,C → D, state D might update twice when A changes
2. **Glitches**: Derived state can be temporarily inconsistent during multi-step updates
3. **Ordering Issues**: Updates may propagate in unexpected order
4. **Zombie Updates**: Old derived values triggering renders before new values arrive

## Proposed Solution: Transaction-Based State Management

Instead of immediate propagation (which causes glitches), we use a transaction model that batches all state changes and computes derived values exactly once per render cycle.

### Core Architecture

```moonbit
// File: src/core/state.mbt

///| Transaction-based state manager - prevents glitches and ensures consistency
pub struct StateManager {
  mut transaction_depth : Int
  mut pending_updates : Array[(Int, () -> Unit)]  // (priority, update_fn)
  mut render_requested : Bool
  mut generation : Int  // Global generation counter
  render_callback : Ref[(() -> Unit)?]  // Set by event loop
}

///| Smart state wrapper with automatic change tracking
pub struct State[T] {
  mut value : T
  mut generation : Int  // When last updated
  mut update_priority : Int  // For ordering updates
  id : Int  // Unique ID for this state
  manager : Ref[StateManager?]
}

///| Derived state that updates synchronously without glitches
pub struct Derived[T] {
  compute : () -> T
  mut cached_value : T
  mut cached_generation : Int
  dependencies : Array[Int]  // IDs of states we depend on
  update_priority : Int
  manager : Ref[StateManager?]
}
```

### Transaction Mechanism

```moonbit
// All state changes happen within transactions
pub fn StateManager::transaction(self : StateManager, updates : () -> Unit) -> Unit {
  self.transaction_depth = self.transaction_depth + 1

  updates()  // Collect all state changes

  self.transaction_depth = self.transaction_depth - 1

  if self.transaction_depth == 0 {
    // Process ALL pending updates in priority order
    self.flush_updates()

    // Then request single render
    if self.render_requested {
      match self.render_callback.val {
        Some(callback) => callback()
        None => ()
      }
      self.render_requested = false
    }
  }
}

pub fn StateManager::flush_updates(self : StateManager) -> Unit {
  // Sort by priority to ensure correct order
  self.pending_updates.sort_by(fn(a, b) { a.0.compare(b.0) })

  // Execute all updates
  for (_, update_fn) in self.pending_updates {
    update_fn()
  }

  self.pending_updates.clear()
  self.generation = self.generation + 1
}
```

### State Implementation

```moonbit
pub fn State::new[T](value : T, priority? : Int = 0) -> State[T] {
  {
    value,
    generation: 0,
    update_priority: priority,
    id: generate_unique_id(),
    manager: get_global_manager()  // Injected by event loop
  }
}

pub fn State::set[T](self : State[T], new_value : T) -> Unit {
  match self.manager.val {
    Some(mgr) => {
      if mgr.transaction_depth > 0 {
        // Inside transaction - defer update
        mgr.pending_updates.push((self.update_priority, fn() {
          self.value = new_value
          self.generation = mgr.generation
        }))
      } else {
        // Auto-wrap in transaction
        mgr.transaction(fn() {
          self.value = new_value
          self.generation = mgr.generation
        })
      }
      mgr.render_requested = true
    }
    None => {
      // Fallback: direct update (during initialization)
      self.value = new_value
    }
  }
}

pub fn State::get[T](self : State[T]) -> T {
  self.value
}

// Convenience for migration from Ref
pub fn State::val[T](self : State[T]) -> T {
  self.value
}
```

### Derived State Implementation

```moonbit
pub fn Derived::new[T](compute : () -> T, priority? : Int = 1) -> Derived[T] {
  let initial = compute()
  {
    compute,
    cached_value: initial,
    cached_generation: -1,
    dependencies: [],  // TODO: Track automatically
    update_priority: priority,
    manager: get_global_manager()
  }
}

pub fn Derived::get[T](self : Derived[T]) -> T {
  match self.manager.val {
    Some(mgr) => {
      if self.cached_generation < mgr.generation {
        // Recompute only if dependencies changed
        self.cached_value = (self.compute)()
        self.cached_generation = mgr.generation
      }
      self.cached_value
    }
    None => (self.compute)()  // Fallback
  }
}
```

## Integration with Event Loop

```moonbit
// File: src/runtime/event_loop.mbt (modified)

pub fn run_event_loop(app, build_ui, on_global_event?) -> Unit {
  // Create state manager
  let state_mgr = StateManager::{
    transaction_depth: 0,
    pending_updates: [],
    render_requested: false,
    generation: 0,
    render_callback: Ref::new(None)
  }

  // Install as global manager
  set_global_manager(state_mgr)

  // Track if we need initial render
  let needs_initial_render = true

  // Set up render callback
  state_mgr.render_callback.val = Some(fn() {
    // Build UI (reads from States - all consistent!)
    let ui = build_ui()

    // Calculate layout and render
    let yoga_root = calculate_layout(ui, width, height)
    render_with_layout(app, ui, yoga_root, 0, 0)

    // Use force=false to leverage Zig's buffer diffing
    app.get_renderer().render(force=false)
  })

  while running.val {
    let event = poll_input_event()

    // Wrap ALL event handling in transaction
    state_mgr.transaction(fn() {
      match event {
        Key(key) => {
          // All state changes in handlers are batched
          dispatch_key_event(ui, key, focused_view_id.val)
        }
        Click(x, y) => {
          // Multiple state changes happen atomically
          dispatch_click(ui, x, y, layout)
        }
        Resize(w, h) => {
          app.resize(w, h)
          // Force render on resize
          state_mgr.render_requested = true
        }
      }
    })
    // Render happens automatically here if any state changed

    // Initial render
    if needs_initial_render {
      state_mgr.render_requested = true
      state_mgr.transaction(fn() {})  // Empty transaction triggers render
      needs_initial_render = false
    }

    sleep_ms(frame_time_ms)
  }
}
```

## Widget Integration

```moonbit
// Example: TextInput using State
pub struct TextInput {
  value : State[String]  // Changed from Ref[String]
  placeholder : String
  width : Double
}

pub fn TextInput::new(value : State[String]) -> TextInput {
  {
    value,
    placeholder: "Type here...",
    width: 30.0,
  }
}

pub impl Component for TextInput with handle_event(self, event) {
  match event {
    Event::Key(key) =>
      match key {
        KeyEvent::Char(c) => {
          // This automatically requests a render
          // And if multiple widgets update, it's all batched!
          self.value.set(self.value.get() + c.to_string())
          true  // Just return handled
        }
        KeyEvent::Backspace => {
          let current = self.value.get()
          if current.length() > 0 {
            self.value.set(current.substring(0, current.length() - 1))
          }
          true
        }
        _ => false
      }
  }
}
```

## Example: Avoiding Glitches

```moonbit
// Problem scenario: Form with interdependent fields
let first_name = State::new("John")
let last_name = State::new("Doe")
let full_name = Derived::new(fn() {
  first_name.get() + " " + last_name.get()
})
let greeting = Derived::new(fn() {
  "Hello, " + full_name.get() + "!"
})

// WITHOUT transactions (causes glitches):
first_name.set("Jane")  // full_name = "Jane Doe" (glitch!)
                        // greeting = "Hello, Jane Doe!" (glitch!)
last_name.set("Smith")  // full_name = "Jane Smith"
                        // greeting = "Hello, Jane Smith!"
// Result: 2 renders, temporary inconsistent state

// WITH transactions (our approach):
state_mgr.transaction(fn() {
  first_name.set("Jane")
  last_name.set("Smith")
})
// full_name computes ONCE as "Jane Smith"
// greeting computes ONCE as "Hello, Jane Smith!"
// Result: 1 render, always consistent state
```

## Migration Strategy

### Phase 1: Add State alongside Ref (Non-breaking)

```moonbit
// Create type alias for gradual migration
pub typealias MutableValue[T] = State[T] | Ref[T]

// Widgets accept either
pub fn TextInput::new(value : MutableValue[String]) -> TextInput
```

### Phase 2: Convert Internal Widget State

```moonbit
// Old widget
pub struct Counter {
  count : Ref[Int]
}

// New widget
pub struct Counter {
  count : State[Int]
}
```

### Phase 3: Update User Code

```moonbit
// Old user code
let counter = Ref::new(0)
counter.val = counter.val + 1

// New user code (option A - explicit)
let counter = State::new(0)
counter.set(counter.get() + 1)

// New user code (option B - with convenience)
let counter = State::new(0)
counter.val = counter.val + 1  // Via operator overloading
```

## Advanced Features

### Batch Updates

```moonbit
// Prevent multiple renders for related changes
pub fn batch(updates : () -> Unit) -> Unit {
  get_global_manager().transaction(updates)
}

// Usage
batch(fn() {
  user_name.set("Alice")
  user_age.set(30)
  user_city.set("NYC")
})  // Only one render!
```

### Computed/Memoized Values

```moonbit
// Expensive computation only runs when dependencies change
let filtered_items = Derived::new(fn() {
  items.get().filter(fn(item) {
    item.name.contains(search_term.get())
  })
})
```

### Effect System (Future)

```moonbit
// Run side effects when state changes
State::effect(counter, fn(new_value) {
  println("Counter changed to: " + new_value.to_string())
})
```

## Performance Benefits

1. **Reduced Renders**: Multiple state changes = one render
2. **No Glitches**: All derived values computed with consistent state
3. **Lazy Computation**: Derived values only recompute when accessed after changes
4. **Buffer Diffing**: Using `force=false` leverages Zig's efficient diffing
5. **Predictable**: Updates happen in defined priority order

## Comparison with Other Approaches

### vs Direct Mutation (Current)

- ❌ Current: No automatic change tracking
- ✅ State: Automatic render triggering

### vs Immediate Signals (Previous attempt)

- ❌ Signals: Glitches, diamond dependencies, ordering issues
- ✅ State: Transaction-based, consistent updates

### vs Virtual DOM

- ❌ VDOM: Heavy diffing overhead
- ✅ State: Lightweight change tracking + native Zig buffer diffing

## Implementation Priority

1. **Core State/StateManager** - Enable automatic render triggering
2. **Event Loop Integration** - Wire up transaction system
3. **Widget Migration** - Convert TextInput, List, etc.
4. **Derived State** - Add computed values
5. **Developer Tools** - State debugging, transaction logging

## Summary

This state management design solves the core problems:

1. **API Compatibility**: Minimal changes, mostly internal
2. **No Glitches**: Transaction-based updates ensure consistency
3. **Performance**: Leverages existing Zig buffer diffing with `force=false`
4. **Ergonomics**: Automatic render triggering without manual calls
5. **Focus Management**: Works seamlessly with existing focus system

The key insight is that we already have efficient buffer diffing in the Zig layer - we just need to:

1. Stop forcing full redraws (`force=true` → `force=false`)
2. Track state changes automatically (State wrapper)
3. Batch updates within transactions (prevent glitches)

This gives us React-like ergonomics with better performance and no virtual DOM overhead!

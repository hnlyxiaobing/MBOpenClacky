# sse.mbt

Server-Sent Events (SSE) support for MoonBit/JS.

This library provides a type-safe interface to the browser's [EventSource API](https://developer.mozilla.org/en-US/docs/Web/API/EventSource) for receiving server-sent events in MoonBit applications targeting JavaScript.

## Features

- Type-safe SSE client implementation
- Fluent API for event handler registration
- Automatic reconnection with configurable retry logic
- Connection state management
- Event message parsing with optional ID tracking
- Property-based testing coverage
- No Dependencies: Built on top of `mizchi/js` bindings.

## Installation

```bash
moon add f4ah6o/sse
```

## Usage

```moonbit nocheck
import sse.{connect, on_message, on_error, on_open, close}

fn main {
  let conn = connect("http://localhost:8080/events")

  conn
    |> on_message(fn(msg) {
      println("Received: \{msg.data}")
    })
    |> on_error(fn(err) {
      println("Error: \{err}")
    })
    |> on_open(fn(_state) {
      println("Connection opened")
    })

  // Close when done
  close(conn)
}
```

### Named Events

```moonbit nocheck
import sse.{connect, on}

let conn = connect("http://localhost:8080/events")

conn
  |> on("notification", fn(msg) {
    println("Notification: \{msg.data}")
  })
  |> on("update", fn(msg) {
    println("Update: \{msg.data}")
  })
```

### Auto-Reconnection

```moonbit nocheck
import sse.{connect, setup_auto_reconnect, on_message}

let conn = connect("http://localhost:8080/events")
  |> setup_auto_reconnect
  |> on_message(fn(msg) {
    println("Received: \{msg.data}")
  })

// Will automatically reconnect on connection loss
// up to max_retries times with reconnect_interval delay
```

### Custom Configuration

```moonbit nocheck
import sse.{
  default_connection_config, connect_with_config, on_message
}

let config = {
  ...default_connection_config("http://localhost:8080/events")
  with_credentials: true
  reconnect_interval: 5000
  max_retries: 5
}

let conn = connect_with_config(config)
  |> on_message(fn(msg) {
    println("Event: \{msg.event_name}, Data: \{msg.data}")
  })
```

## Building & Testing

```bash
# Build for JavaScript target
moon build --target js

# Run tests
moon test --target js

# Update snapshots after behavioral changes
moon test --target js --update
```

## License

Apache-2.0

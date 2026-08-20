///|
/// Layered timeout middleware.
/// Applies route-specific timeouts based on URL path patterns.
/// Falls back to a configurable default timeout for unmatched routes.
/// Note: The actual request-level timeout is enforced by crescent's
/// NativeServeOptions.handler_timeout_ms. This middleware provides
/// route-specific timeout configuration and advisory enforcement.

///|
/// Route timeout configuration.
/// Maps URL path prefixes to timeout durations in milliseconds.
pub(all) struct TimeoutConfig {
  routes : Array[(String, Int)]
  default_ms : Int
}

///|
/// Create a default timeout configuration with tiered timeouts:
/// - /api/brand/*: 90s (license validation, crypto operations)
/// - /api/browser/*: 30s (browser automation)
/// - /api/exchange/*: 20s (exchange rate lookups)
/// - /api/media/video: 600s (video processing)
/// - /api/media/audio: 120s (audio processing)
/// - /api/sessions/:id/chat/stream: 300s (streaming agent conversations)
/// - /api/sessions/:id/chat: 120s (non-streaming agent conversations)
/// - default: 30s
///
/// Chat routes are keyed by their `/chat/stream` and `/chat` suffixes
/// (longest first) so that the streaming variant wins before the plain
/// chat match. `resolve` matches both `has_prefix` (for `/api/*` routes)
/// and `has_suffix` (for `/chat` and `/chat/stream`); the previous
/// `contains` fallback matched any URL containing "/chat" (e.g.
/// `/api/skills/chat-export`), so it was removed.
pub fn default_timeout_config() -> TimeoutConfig {
  {
    routes: [
      ("/api/brand/", 90000),
      ("/api/browser/", 30000),
      ("/api/exchange/", 20000),
      ("/api/media/video", 600000),
      ("/api/media/audio", 120000),
      ("/chat/stream", 300000),
      ("/chat", 120000),
    ],
    default_ms: 30000,
  }
}

///|
/// Resolve the timeout for a given URL path based on the configuration.
/// Routes are checked in order; first match wins. A route matches when
/// the URL either starts with or ends with the configured pattern:
///   - prefix-style routes (`/api/brand/`) match via `has_prefix`
///   - suffix-style routes (`/chat`, `/chat/stream`) match via `has_suffix`
/// Order the routes so longer suffixes precede shorter ones
/// (e.g. `/chat/stream` before `/chat`) to keep the streaming variant
/// from being shadowed by the plain chat match.
///
/// The previous implementation used `has_prefix || contains`, which
/// matched any URL containing the substring (e.g. "/chat" hit
/// `/api/skills/chat-export`), so the `contains` fallback was removed.
pub fn TimeoutConfig::resolve(self : TimeoutConfig, url : String) -> Int {
  let mut i = 0
  while i < self.routes.length() {
    let prefix = self.routes[i].0
    if url.has_prefix(prefix) || url.has_suffix(prefix) {
      return self.routes[i].1
    }
    i = i + 1
  }
  self.default_ms
}

///|
/// Creates timeout middleware that records the intended timeout
/// in the response headers for monitoring/observability.
/// The actual timeout enforcement is handled by crescent's handler_timeout_ms.
pub fn timeout_middleware(
  config? : TimeoutConfig = default_timeout_config(),
) -> @crescent.Middleware {
  let mw : @crescent.Middleware = (event, next) => {
    let url = event.req.url
    let timeout_ms = config.resolve(url)
    // Store the route-specific timeout as a response header for observability
    event.res.headers["X-Timeout-Ms"] = timeout_ms.to_string()
    next()
  }
  mw
}

///|
/// Helper to get the maximum timeout across all route configs.
/// Useful for configuring crescent's NativeServeOptions.handler_timeout_ms.
pub fn TimeoutConfig::max_timeout(self : TimeoutConfig) -> Int {
  let mut max_val = self.default_ms
  let mut i = 0
  while i < self.routes.length() {
    let timeout = self.routes[i].1
    if timeout > max_val {
      max_val = timeout
    }
    i = i + 1
  }
  max_val
}

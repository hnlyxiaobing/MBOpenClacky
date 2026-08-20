///|
/// CLI handler for the `mcp` subcommand group.
///
/// Ruby's `clacky mcp` exposes this CLI as a stdio MCP server so external
/// toolchains (editors, orchestrators) can drive it over JSON-RPC.
///
/// Current status (spec 2026-08-18_16, decision 1 + risk "mcp 依赖 stdio
/// JSON-RPC 基础设施"): the MB-side `StdioTransport` in `lib/mcp` is still a
/// placeholder ("TODO: FFI implementation needed"). The native stdio child
/// process spawn capability required to *serve* JSON-RPC on stdin/stdout is
/// not yet implemented, so this entry point reports a clear, actionable
/// message instead of silently failing. Wiring the real stdio server is a
/// follow-up (phase 2) once the FFI layer lands.

///|
/// Handle the `mcp` subcommand. Reports the stdio-server capability status.
pub fn handle_mcp() -> Unit {
  println("mbopenclacky mcp: stdio MCP server exposure is not yet available.")
  println("")
  println(
    "The native stdio JSON-RPC transport (lib/mcp/stdio_transport.mbt) is",
  )
  println(
    "still a placeholder pending FFI child-process support. This CLI cannot",
  )
  println("yet serve an MCP endpoint on stdin/stdout.")
  println("")
  println("The MCP registry itself is available over the web server REST API")
  println("(POST /api/mcp, etc.). Start it with:  mbopenclacky server")
}

/*
 * stderr sink for agent diagnostics.
 *
 * `println` writes to stdout, so anything emitted through it corrupts the
 * machine-readable modes (`--message --json`, `eval --live`) — the CLI
 * contract had to declare "the JSON payload is the last line of stdout" to
 * cope with it. Routing diagnostics to stderr keeps stdout parseable.
 *
 * MoonBit has no portable stderr primitive (moonbitlang/async keeps its
 * `eprintln` in an internal package), hence this one-purpose stub.
 */

#include <moonbit.h>
#include <stdint.h>
#include <stdio.h>

MOONBIT_FFI_EXPORT
void mbopenclacky_write_stderr(moonbit_bytes_t bytes) {
  int32_t len = Moonbit_array_length(bytes);
  if (len > 0) {
    fwrite(bytes, 1, (size_t)len, stderr);
  }
  fputc('\n', stderr);
  fflush(stderr);
}
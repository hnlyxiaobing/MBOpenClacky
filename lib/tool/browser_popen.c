// browser_popen.c — synchronous shell runner for screenshot downscaling.
// MBOpenClacky
//
// The screenshot producer (browser_screenshot.mbt) must downscale PNG
// screenshots to 800px wide (Ruby uses the chunky_png gem). MoonBit core
// has no image/zlib package and @process.run is async while the browser
// tool chain is synchronous, so this single-purpose stub runs a shell
// command synchronously via popen and returns the exit code. Output is
// captured by the caller through redirection inside the command.
//
// Kept separate from stat_native.c (same rationale: single-purpose stubs,
// do not extend either surface).

#include <moonbit.h>
#include <stdlib.h>
#include <stdio.h>

#ifdef _WIN32
  #define WIN32_LEAN_AND_MEAN
  #include <windows.h>
  #include <process.h>
#else
  #include <sys/wait.h>
  #include <unistd.h>
#endif

// ── UTF-16 (moonbit_string_t) → UTF-8 C string (malloc'd, caller frees) ────
// Same conversion as stat_native.c (kept static per translation unit).

static char *mbstr_to_utf8(moonbit_string_t s) {
  int32_t len = Moonbit_array_length(s);
  int cap = len * 3 + 1;
  char *buf = (char *)malloc(cap);
  if (!buf) return NULL;
  int j = 0;
  for (int32_t i = 0; i < len; i++) {
    uint16_t c = s[i];
    if (c < 0x80) {
      buf[j++] = (char)c;
    } else if (c < 0x800) {
      buf[j++] = (char)(0xC0 | (c >> 6));
      buf[j++] = (char)(0x80 | (c & 0x3F));
    } else if (c >= 0xD800 && c <= 0xDBFF && i + 1 < len) {
      uint16_t lo = s[i + 1];
      uint32_t cp =
        0x10000 +
        (((uint32_t)(c - 0xD800)) << 10) + (uint32_t)(lo - 0xDC00);
      buf[j++] = (char)(0xF0 | (cp >> 18));
      buf[j++] = (char)(0x80 | ((cp >> 12) & 0x3F));
      buf[j++] = (char)(0x80 | ((cp >> 6) & 0x3F));
      buf[j++] = (char)(0x80 | (cp & 0x3F));
      i++;
    } else {
      buf[j++] = (char)(0xE0 | (c >> 12));
      buf[j++] = (char)(0x80 | ((c >> 6) & 0x3F));
      buf[j++] = (char)(0x80 | (c & 0x3F));
    }
  }
  buf[j] = 0;
  return buf;
}

/// Run a shell command synchronously, drain its stdout (the caller
/// redirects real output to a file inside the command). Returns the child
/// exit code (0 = success), or -1 when the shell cannot be spawned.
///
/// Windows: moonbit_string_t is UTF-16LE — pass straight to _wsystem, so
/// the temp paths embedded in the command survive the ANSI codepage issue
/// that would corrupt UTF-8 paths under _popen.
/// POSIX:   UTF-16 → UTF-8 → popen().
MOONBIT_FFI_EXPORT
int64_t mbopenclacky_popen_run(moonbit_string_t cmd) {
#ifdef _WIN32
  int r = _wsystem((const wchar_t *)cmd);
  return r == -1 ? -1 : (int64_t)r;
#else
  char *c = mbstr_to_utf8(cmd);
  if (!c) return -1;
  FILE *f = popen(c, "r");
  free(c);
  if (!f) return -1;
  // Drain and discard stdout; real output must be redirected to a file
  // inside the command by the caller.
  char buf[4096];
  while (fread(buf, 1, sizeof(buf), f) > 0) {}
  int st = pclose(f);
  if (st == -1) return -1;
  if (!WIFEXITED(st)) return -1;
  return (int64_t)WEXITSTATUS(st);
#endif
}

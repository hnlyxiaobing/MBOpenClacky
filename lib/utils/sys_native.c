// sys_native.c — Platform-native chdir / osrelease for MBOpenClacky
// Windows: SetCurrentDirectoryA / GetCurrentDirectoryA (kernel32)
// POSIX:   chdir / getcwd (unistd.h)
//
// RETAINED (S-FFI-08, specs/completed/2026-07-25_ffi-08-residual-ffi-pty.md):
// chdir and uname/osrelease have no official MoonBit API
// (docs/ffi-c-code-report.md "FFI 必要性总结": 操作系统 API — 成立; §7
// lib/utils). getcwd moved to moonbitlang/core in S-01; this file is the
// project's single remaining sys-level FFI surface — do not extend it.

#include <moonbit.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
  #define WIN32_LEAN_AND_MEAN
  #include <windows.h>
  #pragma comment(lib, "kernel32.lib")
#else
  #include <unistd.h>
  #include <sys/utsname.h>
#endif

// ── UTF-8 to UTF-16 helper ──────────────────────────────────────────────────

/// Count UTF-16 code units needed for a NUL-terminated ASCII/UTF-8 string.
static int32_t utf8_to_utf16_len(const char *s) {
  int32_t n = 0;
  while (*s) {
    unsigned char c = (unsigned char)*s;
    if (c < 0x80) {
      n += 1;
      s += 1;
    } else if (c < 0xE0) {
      n += 1; // 2-byte UTF-8 → 1 UTF-16 code unit (BMP)
      s += 2;
    } else if (c < 0xF0) {
      n += 1; // 3-byte UTF-8 → 1 UTF-16 code unit (BMP)
      s += 3;
    } else {
      n += 2; // 4-byte UTF-8 → 2 UTF-16 code units (surrogate pair)
      s += 4;
    }
  }
  return n;
}

/// Convert a NUL-terminated ASCII/UTF-8 string to UTF-16LE.
/// `dst` must have enough space (use utf8_to_utf16_len first).
/// Returns number of uint16_t code units written (excluding NUL terminator).
static int32_t utf8_to_utf16(const char *s, uint16_t *dst) {
  uint16_t *start = dst;
  while (*s) {
    unsigned char c = (unsigned char)*s;
    if (c < 0x80) {
      *dst++ = (uint16_t)c;
      s += 1;
    } else if (c < 0xE0) {
      uint32_t cp = ((uint32_t)(c & 0x1F) << 6) | ((uint32_t)(s[1] & 0x3F));
      *dst++ = (uint16_t)cp;
      s += 2;
    } else if (c < 0xF0) {
      uint32_t cp = ((uint32_t)(c & 0x0F) << 12) | ((uint32_t)(s[1] & 0x3F) << 6) | ((uint32_t)(s[2] & 0x3F));
      *dst++ = (uint16_t)cp;
      s += 3;
    } else {
      uint32_t cp = ((uint32_t)(c & 0x07) << 18) | ((uint32_t)(s[1] & 0x3F) << 12) | ((uint32_t)(s[2] & 0x3F) << 6) | ((uint32_t)(s[3] & 0x3F));
      cp -= 0x10000;
      *dst++ = (uint16_t)(0xD800 | (cp >> 10));
      *dst++ = (uint16_t)(0xDC00 | (cp & 0x3FF));
      s += 4;
    }
  }
  return (int32_t)(dst - start);
}

/// Create a moonbit_string_t from a NUL-terminated C string.
/// Returns an empty string on allocation failure.
static moonbit_string_t mbstr_from_cstr(const char *s) {
  if (!s) s = "";
  int32_t utf16_len = utf8_to_utf16_len(s);
  moonbit_string_t result = moonbit_make_string_raw(utf16_len);
  if (!result) return moonbit_make_string_raw(0);
  utf8_to_utf16(s, result);
  return result;
}

// ── chdir FFI ───────────────────────────────────────────────────────────────

/// Change the current working directory.
/// Returns 0 on success, -1 on error.
MOONBIT_FFI_EXPORT
int32_t mbopenclacky_chdir(moonbit_string_t path) {
  // Convert MoonBit UTF-16 string to UTF-8 C string
  int32_t len = Moonbit_array_length(path);
  int cap = len * 3 + 1;
  char *buf = (char *)malloc(cap);
  if (!buf) return -1;
  int j = 0;
  for (int32_t i = 0; i < len; i++) {
    uint16_t c = path[i];
    if (c < 0x80) {
      buf[j++] = (char)c;
    } else if (c < 0x800) {
      buf[j++] = (char)(0xC0 | (c >> 6));
      buf[j++] = (char)(0x80 | (c & 0x3F));
    } else {
      buf[j++] = (char)(0xE0 | (c >> 12));
      buf[j++] = (char)(0x80 | ((c >> 6) & 0x3F));
      buf[j++] = (char)(0x80 | (c & 0x3F));
    }
  }
  buf[j] = '\0';

  int result;
#ifdef _WIN32
  result = SetCurrentDirectoryA(buf) ? 0 : -1;
#else
  result = chdir(buf);
#endif
  free(buf);
  return result;
}

// ── osrelease FFI ───────────────────────────────────────────────────────────

/// Get the kernel release string (same content as
/// /proc/sys/kernel/osrelease). POSIX: uname(). Windows: empty string.
/// Used instead of reading /proc directly because the x/fs reader sizes
/// the buffer via fseek/ftell, which yields 0 bytes on procfs files.
MOONBIT_FFI_EXPORT
moonbit_string_t mbopenclacky_osrelease(void) {
#ifdef _WIN32
  return moonbit_make_string_raw(0);
#else
  struct utsname u;
  if (uname(&u) != 0) return moonbit_make_string_raw(0);
  return mbstr_from_cstr(u.release);
#endif
}

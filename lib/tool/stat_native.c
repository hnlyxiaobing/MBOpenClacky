// stat_native.c — file size / mtime for read-only tools (glob mtime sort,
// grep/file_reader 1MB guards). MBOpenClacky
//
// x/fs has no stat API; sys_native.c is the retained single sys-level FFI
// surface (do not extend it), so this separate stub is added for the tool
// package only (lib/tool/moon.pkg native-stub).
//
// Windows: MoonBit String is UTF-16LE → pass straight to _wstat64.
// POSIX:   UTF-16 → UTF-8 → stat().

#include <moonbit.h>
#include <stdlib.h>

#ifdef _WIN32
  #define WIN32_LEAN_AND_MEAN
  #include <windows.h>
  #include <sys/stat.h>
  #pragma comment(lib, "kernel32.lib")
#else
  #include <sys/stat.h>
  #include <unistd.h>
#endif

// ── UTF-16 (moonbit_string_t) → UTF-8 C string (malloc'd, caller frees) ────

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

// ── stat dispatch ───────────────────────────────────────────────────────────

#ifdef _WIN32
static int stat_path(moonbit_string_t path, struct _stat64 *st) {
  return _wstat64((const wchar_t *)path, st);
}
#else
static int stat_path(moonbit_string_t path, struct stat *st) {
  char *p = mbstr_to_utf8(path);
  if (!p) return -1;
  int r = stat(p, st);
  free(p);
  return r;
}
#endif

/// File size in bytes; -1 on error (missing file, permission, etc.)
MOONBIT_FFI_EXPORT
int64_t mbopenclacky_file_size(moonbit_string_t path) {
#ifdef _WIN32
  struct _stat64 st;
#else
  struct stat st;
#endif
  if (stat_path(path, &st) != 0) return -1;
  return (int64_t)st.st_size;
}

/// Modification time in epoch seconds; -1 on error.
MOONBIT_FFI_EXPORT
int64_t mbopenclacky_mtime_sec(moonbit_string_t path) {
#ifdef _WIN32
  struct _stat64 st;
#else
  struct stat st;
#endif
  if (stat_path(path, &st) != 0) return -1;
  return (int64_t)st.st_mtime;
}

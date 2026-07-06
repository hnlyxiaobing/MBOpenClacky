/*
 * Git command execution FFI for MBOpenClacky.
 * Uses popen() to capture command stdout for git panel handlers.
 */

#include <moonbit.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#ifdef _WIN32
  #define popen _popen
  #define pclose _pclose
#endif

/* ── UTF-16 ↔ UTF-8 helpers (same as sys_native.c) ──────────────────────── */

static int32_t git_utf8_to_utf16_len(const char *s) {
  int32_t n = 0;
  while (*s) {
    unsigned char c = (unsigned char)*s;
    if (c < 0x80) { n += 1; s += 1; }
    else if (c < 0xE0) { n += 1; s += 2; }
    else if (c < 0xF0) { n += 1; s += 3; }
    else { n += 2; s += 4; }
  }
  return n;
}

static int32_t git_utf8_to_utf16(const char *s, uint16_t *dst) {
  uint16_t *start = dst;
  while (*s) {
    unsigned char c = (unsigned char)*s;
    if (c < 0x80) {
      *dst++ = (uint16_t)c; s += 1;
    } else if (c < 0xE0) {
      uint32_t cp = ((uint32_t)(c & 0x1F) << 6) | ((uint32_t)(s[1] & 0x3F));
      *dst++ = (uint16_t)cp; s += 2;
    } else if (c < 0xF0) {
      uint32_t cp = ((uint32_t)(c & 0x0F) << 12) | ((uint32_t)(s[1] & 0x3F) << 6) | ((uint32_t)(s[2] & 0x3F));
      *dst++ = (uint16_t)cp; s += 3;
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

static moonbit_string_t git_mbstr_from_cstr(const char *s) {
  if (!s) s = "";
  int32_t utf16_len = git_utf8_to_utf16_len(s);
  moonbit_string_t result = moonbit_make_string_raw(utf16_len);
  if (!result) return moonbit_make_string_raw(0);
  git_utf8_to_utf16(s, result);
  return result;
}

static char *git_mbstr_to_utf8(moonbit_string_t str) {
  int len = Moonbit_array_length(str);
  int cap = len * 3 + 1;
  char *buf = (char *)malloc(cap);
  if (!buf) return NULL;
  int j = 0;
  for (int i = 0; i < len; i++) {
    uint16_t c = str[i];
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
  return buf;
}

/* ── popen-based command execution ───────────────────────────────────────── */

#define GIT_EXEC_BUF_SIZE 4096

/// Execute a shell command and capture its stdout output.
/// Returns the captured output as a MoonBit string.
MOONBIT_FFI_EXPORT
moonbit_string_t mbopenclacky_git_exec(moonbit_string_t command) {
  char *cmd = git_mbstr_to_utf8(command);
  if (!cmd) return moonbit_make_string_raw(0);

  FILE *fp = popen(cmd, "r");
  free(cmd);
  if (!fp) return moonbit_make_string_raw(0);

  /* Read all output into a dynamically growing buffer */
  char *output = (char *)malloc(GIT_EXEC_BUF_SIZE);
  if (!output) { pclose(fp); return moonbit_make_string_raw(0); }
  int total = 0;
  int capacity = GIT_EXEC_BUF_SIZE;
  int bytes_read;
  char tmp[1024];

  while ((bytes_read = (int)fread(tmp, 1, sizeof(tmp), fp)) > 0) {
    if (total + bytes_read + 1 > capacity) {
      capacity = (total + bytes_read + 1) * 2;
      char *new_output = (char *)realloc(output, capacity);
      if (!new_output) { free(output); pclose(fp); return moonbit_make_string_raw(0); }
      output = new_output;
    }
    memcpy(output + total, tmp, bytes_read);
    total += bytes_read;
  }
  output[total] = '\0';
  pclose(fp);

  moonbit_string_t result = git_mbstr_from_cstr(output);
  free(output);
  return result;
}

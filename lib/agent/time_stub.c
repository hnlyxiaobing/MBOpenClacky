/*
 * Time stub for MBOpenClacky session timestamps.
 * Provides ms_since_epoch() and ISO 8601 local-time helpers for native targets.
 */

#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <moonbit.h>

/* Copy a pure-ASCII buffer into a MoonBit (UTF-16) string. */
static moonbit_string_t mb_ascii_string(const char *s, int len) {
  moonbit_string_t result = moonbit_make_string_raw(len);
  if (!result) return moonbit_make_string_raw(0);
  for (int i = 0; i < len; i++) {
    ((uint16_t *)result)[i] = (uint16_t)(unsigned char)s[i];
  }
  return result;
}

/* Format "YYYY-MM-DDTHH:MM:SS±HH:MM" from civil parts + offset minutes. */
static moonbit_string_t mb_format_iso(
  int year, int mon, int day, int hour, int min, int sec, long offset_min
) {
  char sign = offset_min < 0 ? '-' : '+';
  long abs_min = offset_min < 0 ? -offset_min : offset_min;
  char buf[40];
  int n = snprintf(
    buf, sizeof(buf), "%04d-%02d-%02dT%02d:%02d:%02d%c%02d:%02d",
    year, mon, day, hour, min, sec,
    sign, (int)(abs_min / 60), (int)(abs_min % 60)
  );
  if (n <= 0) return moonbit_make_string_raw(0);
  return mb_ascii_string(buf, n);
}

#ifdef _WIN32

#include <windows.h>

/* Current local UTC offset in minutes (handles DST via TIME_ZONE_INFORMATION). */
static long mb_local_offset_minutes() {
  TIME_ZONE_INFORMATION tzi;
  DWORD r = GetTimeZoneInformation(&tzi);
  LONG bias = tzi.Bias;
  if (r == TIME_ZONE_ID_DAYLIGHT) {
    bias += tzi.DaylightBias;
  } else if (r == TIME_ZONE_ID_STANDARD) {
    bias += tzi.StandardBias;
  }
  return -(long)bias;
}

MOONBIT_FFI_EXPORT
int64_t mbopenclacky_ms_since_epoch() {
  FILETIME ft;
  GetSystemTimeAsFileTime(&ft);
  int64_t t = ((int64_t)ft.dwHighDateTime << 32) | (int64_t)ft.dwLowDateTime;
  /* FILETIME counts 100ns intervals since 1601-01-01; convert to Unix ms. */
  return t / 10000 - 11644473600000LL;
}

MOONBIT_FFI_EXPORT
moonbit_string_t mbopenclacky_iso8601_now() {
  SYSTEMTIME lt;
  GetLocalTime(&lt);
  return mb_format_iso(
    lt.wYear, lt.wMonth, lt.wDay, lt.wHour, lt.wMinute, lt.wSecond,
    mb_local_offset_minutes()
  );
}

MOONBIT_FFI_EXPORT
moonbit_string_t mbopenclacky_ms_to_iso8601_local(int64_t ms) {
  /* Shift by the local offset, then render the shifted value as UTC civil
     time — this yields local wall-clock parts without historical TZ data. */
  int64_t local_ms = ms + (int64_t)mb_local_offset_minutes() * 60000LL;
  int64_t ft100 = (local_ms + 11644473600000LL) * 10000LL;
  FILETIME ft;
  ft.dwLowDateTime = (DWORD)(ft100 & 0xFFFFFFFFLL);
  ft.dwHighDateTime = (DWORD)((uint64_t)ft100 >> 32);
  SYSTEMTIME st;
  if (!FileTimeToSystemTime(&ft, &st)) return moonbit_make_string_raw(0);
  return mb_format_iso(
    st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond,
    mb_local_offset_minutes()
  );
}

#else

#include <time.h>
#include <sys/time.h>

int64_t mbopenclacky_ms_since_epoch() {
  struct timeval tv;
  gettimeofday(&tv, 0);
  return (int64_t)tv.tv_sec * 1000 + tv.tv_usec / 1000;
}

static moonbit_string_t mb_iso_from_time_t(time_t t) {
  struct tm tmv;
  if (!localtime_r(&t, &tmv)) return moonbit_make_string_raw(0);
  return mb_format_iso(
    tmv.tm_year + 1900, tmv.tm_mon + 1, tmv.tm_mday,
    tmv.tm_hour, tmv.tm_min, tmv.tm_sec,
    (long)(tmv.tm_gmtoff / 60)
  );
}

moonbit_string_t mbopenclacky_iso8601_now() {
  return mb_iso_from_time_t(time(NULL));
}

moonbit_string_t mbopenclacky_ms_to_iso8601_local(int64_t ms) {
  return mb_iso_from_time_t((time_t)(ms / 1000));
}

#endif

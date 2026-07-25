/*
 * Time stub for MBOpenClacky: local UTC offset detection only.
 * Millisecond timestamps and ISO 8601 formatting are handled by
 * moonbitlang/core/env and moonbitlang/x/time respectively.
 *
 * RETAINED (S-FFI-08, specs/completed/2026-07-25_ffi-08-residual-ffi-pty.md):
 * local timezone offset is the one remaining time API with no official
 * MoonBit equivalent (docs/ffi-c-code-report.md "FFI 必要性总结": 系统时钟 —
 * 仅"本地时区"成立; §2 lib/agent). Do not extend this file with new FFI.
 */

#include <stdint.h>
#include <moonbit.h>

#ifdef _WIN32

#include <windows.h>

MOONBIT_FFI_EXPORT
int32_t mbopenclacky_local_offset_minutes() {
  TIME_ZONE_INFORMATION tzi;
  DWORD r = GetTimeZoneInformation(&tzi);
  LONG bias = tzi.Bias;
  if (r == TIME_ZONE_ID_DAYLIGHT) {
    bias += tzi.DaylightBias;
  } else if (r == TIME_ZONE_ID_STANDARD) {
    bias += tzi.StandardBias;
  }
  return (int32_t)(-(long)bias);
}

#else

#include <time.h>

MOONBIT_FFI_EXPORT
int32_t mbopenclacky_local_offset_minutes() {
  time_t t = time(NULL);
  struct tm tmv;
  if (!localtime_r(&t, &tmv)) return 0;
  return (int32_t)(tmv.tm_gmtoff / 60);
}

#endif

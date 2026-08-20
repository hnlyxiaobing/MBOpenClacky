/*
 * Time stub for lib/billing: local UTC offset detection only.
 *
 * Mirrors lib/agent/time_stub.c (S-FFI-08) but exports a distinct symbol
 * to avoid duplicate-symbol link errors when both packages are linked
 * into the same native binary (lib/agent imports lib/billing, so
 * lib/billing cannot reuse lib/agent's helper).
 *
 * Needed for Ruby-aligned billing semantics (spec 21 decision 7):
 * per-month file naming, calendar period boundaries and ISO 8601
 * timestamps all require the local timezone offset.
 */

#include <stdint.h>
#include <moonbit.h>

#ifdef _WIN32

#include <windows.h>

MOONBIT_FFI_EXPORT
int32_t mbopenclacky_billing_local_offset_minutes() {
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
int32_t mbopenclacky_billing_local_offset_minutes() {
  time_t t = time(NULL);
  struct tm tmv;
  if (!localtime_r(&t, &tmv)) return 0;
  return (int32_t)(tmv.tm_gmtoff / 60);
}

#endif

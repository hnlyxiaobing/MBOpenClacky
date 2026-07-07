/*
 * Time stub for MBOpenClacky billing timestamps.
 * Provides milliseconds since the Unix epoch for native targets.
 */

#include <stdint.h>
#include <moonbit.h>

#ifdef _WIN32

#include <windows.h>

MOONBIT_FFI_EXPORT
int64_t mb_billing_ms_since_epoch() {
  FILETIME ft;
  GetSystemTimeAsFileTime(&ft);
  int64_t t = ((int64_t)ft.dwHighDateTime << 32) | (int64_t)ft.dwLowDateTime;
  /* FILETIME counts 100ns intervals since 1601-01-01; convert to Unix ms. */
  return t / 10000 - 11644473600000LL;
}

#else

#include <sys/time.h>

int64_t mb_billing_ms_since_epoch() {
  struct timeval tv;
  gettimeofday(&tv, 0);
  return (int64_t)tv.tv_sec * 1000 + tv.tv_usec / 1000;
}

#endif

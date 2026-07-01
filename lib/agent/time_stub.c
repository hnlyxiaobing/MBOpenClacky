/*
 * Time stub for MBOpenClacky session timestamps.
 * Provides ms_since_epoch() for native targets.
 */

#include <stdint.h>
#include <moonbit.h>

#ifdef _WIN32

#include <windows.h>

MOONBIT_FFI_EXPORT
int64_t mbopenclacky_ms_since_epoch() {
  FILETIME ft;
  GetSystemTimeAsFileTime(&ft);
  return (((int64_t)ft.dwHighDateTime << 32) | (int64_t)ft.dwLowDateTime) / 10000;
}

#else

#include <sys/time.h>

int64_t mbopenclacky_ms_since_epoch() {
  struct timeval tv;
  gettimeofday(&tv, 0);
  return tv.tv_sec * 1000 + tv.tv_usec / 1000;
}

#endif
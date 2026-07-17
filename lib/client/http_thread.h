#ifndef MBOPENCLACKY_HTTP_THREAD_H
#define MBOPENCLACKY_HTTP_THREAD_H

#include <stdint.h>
#include "moonbit.h"

#ifdef __cplusplus
extern "C" {
#endif

MOONBIT_FFI_EXPORT
int32_t mbopenclacky_start_http_thread(
  moonbit_string_t method_mbt,
  moonbit_string_t url_mbt,
  moonbit_string_t headers_mbt,
  moonbit_string_t body_mbt,
  int32_t timeout_ms,
  int32_t write_fd
);

#ifdef __cplusplus
}
#endif

#endif

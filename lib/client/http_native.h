#ifndef MBOPENCLACKY_HTTP_NATIVE_H
#define MBOPENCLACKY_HTTP_NATIVE_H

#include <stdint.h>
#include "moonbit.h"

#ifdef __cplusplus
extern "C" {
#endif

MOONBIT_FFI_EXPORT
int32_t mbopenclacky_http_post(
  moonbit_string_t method_mbt,
  moonbit_string_t url_mbt,
  moonbit_string_t headers_mbt,
  moonbit_string_t body_mbt,
  int32_t timeout_ms,
  moonbit_bytes_t resp_body_buf,
  moonbit_bytes_t meta_buf,
  moonbit_bytes_t error_buf
);

#ifdef __cplusplus
}
#endif

#endif

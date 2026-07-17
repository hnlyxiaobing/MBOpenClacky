/*
 * HTTP transport FFI stub for MBOpenClacky.
 * Provides synchronous HTTP POST via WinHTTP (Windows) or libcurl (Linux/macOS).
 *
 * FFI contract:
 *   - method, url, headers, body: input as MoonBit String (UTF-16, moonbit_string_t)
 *   - headers: formatted as "Key: Value\r\n" pairs (may be empty)
 *   - resp_body_buf: pre-allocated buffer for response body
 *   - meta_buf: 8-byte output buffer:
 *       bytes [0..3] = HTTP status code (little-endian int32)
 *       bytes [4..7] = response body size in bytes (little-endian int32)
 *   - error_buf: pre-allocated buffer for error message (null-terminated)
 *   - Returns 0 on success, -1 on transport error
 */

#include <moonbit.h>
#include <stdint.h>
#include <string.h>

#include "http_native.h"

/* Helper: write status and body_size into meta_buf (little-endian) */
static void write_meta(
  moonbit_bytes_t meta_buf, int32_t http_status, int32_t body_size
) {
  meta_buf[0] = (uint8_t)(http_status & 0xFF);
  meta_buf[1] = (uint8_t)((http_status >> 8) & 0xFF);
  meta_buf[2] = (uint8_t)((http_status >> 16) & 0xFF);
  meta_buf[3] = (uint8_t)((http_status >> 24) & 0xFF);
  meta_buf[4] = (uint8_t)(body_size & 0xFF);
  meta_buf[5] = (uint8_t)((body_size >> 8) & 0xFF);
  meta_buf[6] = (uint8_t)((body_size >> 16) & 0xFF);
  meta_buf[7] = (uint8_t)((body_size >> 24) & 0xFF);
}

/* Helper: write error message into error_buf */
static void write_error(moonbit_bytes_t error_buf, const char *msg) {
  int elen = (int)strlen(msg);
  int cap = Moonbit_array_length(error_buf);
  if (elen > cap - 1) elen = cap - 1;
  memcpy(error_buf, msg, (size_t)elen);
  error_buf[elen] = 0;
}

/*
 * Convert MoonBit String (UTF-16, moonbit_string_t) to null-terminated UTF-8 C string.
 * Returns malloc'd buffer; caller must free.
 * Sets *out_len to the UTF-8 byte length (excluding null terminator).
 */
static char *moonbit_string_to_cstr(moonbit_string_t str, int *out_len) {
  int len = Moonbit_array_length(str);
  /* Worst case: each UTF-16 code unit → 3 UTF-8 bytes, plus null */
  char *buf = (char *)malloc((size_t)len * 3 + 1);
  if (!buf) {
    if (out_len) *out_len = 0;
    return NULL;
  }
  int j = 0;
  for (int i = 0; i < len; i++) {
    uint16_t c = str[i];
    if (c < 0x80) {
      buf[j++] = (char)c;
    } else if (c < 0x800) {
      buf[j++] = (char)(0xC0 | (c >> 6));
      buf[j++] = (char)(0x80 | (c & 0x3F));
    } else {
      /* Check for surrogate pair (characters outside BMP) */
      if (c >= 0xD800 && c <= 0xDBFF && i + 1 < len) {
        uint16_t c2 = str[i + 1];
        if (c2 >= 0xDC00 && c2 <= 0xDFFF) {
          uint32_t cp = 0x10000 + ((uint32_t)(c - 0xD800) << 10) + (c2 - 0xDC00);
          buf[j++] = (char)(0xF0 | (cp >> 18));
          buf[j++] = (char)(0x80 | ((cp >> 12) & 0x3F));
          buf[j++] = (char)(0x80 | ((cp >> 6) & 0x3F));
          buf[j++] = (char)(0x80 | (cp & 0x3F));
          i++;
          continue;
        }
      }
      buf[j++] = (char)(0xE0 | (c >> 12));
      buf[j++] = (char)(0x80 | ((c >> 6) & 0x3F));
      buf[j++] = (char)(0x80 | (c & 0x3F));
    }
  }
  buf[j] = '\0';
  if (out_len) *out_len = j;
  return buf;
}

#ifdef _WIN32

#include <windows.h>
#include <winhttp.h>
#pragma comment(lib, "winhttp.lib")

/* Parse "https://host[:port]/path" into wide-char components. */
static int parse_url(
  const char *url,
  wchar_t *host, int host_cap,
  wchar_t *path, int path_cap,
  int *use_https, int *port
) {
  const char *p = url;
  *use_https = 1;
  *port = 443;

  if (strncmp(p, "https://", 8) == 0) {
    p += 8;
  } else if (strncmp(p, "http://", 7) == 0) {
    p += 7;
    *use_https = 0;
    *port = 80;
  } else {
    return -1;
  }

  const char *path_sep = strchr(p, '/');
  int host_len = path_sep ? (int)(path_sep - p) : (int)strlen(p);

  /* Check for :port in host */
  const char *colon = NULL;
  for (int i = 0; i < host_len; i++) {
    if (p[i] == ':') { colon = &p[i]; break; }
  }

  if (colon) {
    int name_len = (int)(colon - p);
    if (name_len >= host_cap) return -1;
    MultiByteToWideChar(CP_UTF8, 0, p, name_len, host, host_cap);
    host[name_len] = 0;
    *port = atoi(colon + 1);
  } else {
    if (host_len >= host_cap) return -1;
    MultiByteToWideChar(CP_UTF8, 0, p, host_len, host, host_cap);
    host[host_len] = 0;
  }

  if (path_sep) {
    int path_len = (int)strlen(path_sep);
    if (path_len >= path_cap) return -1;
    MultiByteToWideChar(CP_UTF8, 0, path_sep, path_len, path, path_cap);
    path[path_len] = 0;
  } else {
    path[0] = '/';
    path[1] = 0;
  }
  return 0;
}

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
) {
  int32_t result = -1;
  int method_len = 0, url_len = 0, headers_len = 0, body_len = 0;
  char *method = moonbit_string_to_cstr(method_mbt, &method_len);
  char *url = moonbit_string_to_cstr(url_mbt, &url_len);
  char *headers_str = moonbit_string_to_cstr(headers_mbt, &headers_len);
  char *body = moonbit_string_to_cstr(body_mbt, &body_len);
  int resp_cap = Moonbit_array_length(resp_body_buf);

  HINTERNET session = NULL, connect = NULL, request = NULL;
  wchar_t w_host[512], w_path[4096];
  int use_https, port;

  write_meta(meta_buf, 0, 0);

  if (!url || !method) {
    write_error(error_buf, "string conversion failed");
    goto win_done;
  }

  if (parse_url(url, w_host, 512, w_path, 4096, &use_https, &port) != 0) {
    write_error(error_buf, "invalid URL format");
    goto win_done;
  }

  session = WinHttpOpen(
    L"MBOpenClacky/0.1",
    WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
    WINHTTP_NO_PROXY_NAME,
    WINHTTP_NO_PROXY_BYPASS, 0
  );
  if (!session) {
    write_error(error_buf, "WinHttpOpen failed");
    goto win_done;
  }
  int connect_timeout = timeout_ms > 10000 ? 10000 : timeout_ms;
  WinHttpSetTimeouts(session, timeout_ms, connect_timeout, timeout_ms, timeout_ms);

  connect = WinHttpConnect(session, w_host, (INTERNET_PORT)port, 0);
  if (!connect) goto win_done;

  wchar_t w_method[16];
  MultiByteToWideChar(CP_UTF8, 0, method, -1, w_method, 16);
  DWORD flags = use_https ? WINHTTP_FLAG_SECURE : 0;

  request = WinHttpOpenRequest(
    connect, w_method, w_path,
    NULL, WINHTTP_NO_REFERER,
    WINHTTP_DEFAULT_ACCEPT_TYPES, flags
  );
  if (!request) goto win_done;

  /* SSL certificate errors are NOT ignored in production */

  if (headers_len > 0) {
    wchar_t w_headers[16384];
    int whl = MultiByteToWideChar(CP_UTF8, 0, headers_str, headers_len, w_headers, 16380);
    if (whl <= 0) {
      write_error(error_buf, "headers too long for WinHTTP buffer");
      goto win_done;
    }
    w_headers[whl] = 0;
    WinHttpAddRequestHeaders(
      request, w_headers, (ULONG)-1L,
      WINHTTP_ADDREQ_FLAG_ADD | WINHTTP_ADDREQ_FLAG_REPLACE
    );
  }

  BOOL sent = WinHttpSendRequest(
    request, WINHTTP_NO_ADDITIONAL_HEADERS, 0,
    body_len > 0 ? (LPVOID)body : WINHTTP_NO_REQUEST_DATA,
    (DWORD)body_len, 0, NULL
  );
  if (!sent) goto win_done;
  if (!WinHttpReceiveResponse(request, NULL)) goto win_done;

  DWORD status_code = 0, status_size = sizeof(status_code);
  WinHttpQueryHeaders(
    request, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
    WINHTTP_HEADER_NAME_BY_INDEX, &status_code, &status_size, WINHTTP_NO_HEADER_INDEX
  );

  int32_t total_read = 0;
  for (;;) {
    DWORD avail = 0;
    if (!WinHttpQueryDataAvailable(request, &avail)) break;
    if (avail == 0) break;
    DWORD to_read = (DWORD)(resp_cap - total_read - 1);
    if (to_read > avail) to_read = avail;
    if (to_read == 0) break;
    DWORD got = 0;
    if (!WinHttpReadData(request, resp_body_buf + total_read, to_read, &got)) break;
    total_read += (int32_t)got;
    if (got == 0) break;
  }
  resp_body_buf[total_read] = 0;
  write_meta(meta_buf, (int32_t)status_code, total_read);
  result = 0;

win_done:
  if (result != 0) {
    char errbuf[256];
    snprintf(errbuf, sizeof(errbuf), "WinHTTP error: 0x%08lX", GetLastError());
    write_error(error_buf, errbuf);
  }
  if (request) WinHttpCloseHandle(request);
  if (connect) WinHttpCloseHandle(connect);
  if (session) WinHttpCloseHandle(session);
  free(method);
  free(url);
  free(headers_str);
  free(body);
  return result;
}

#else
/* Linux/macOS: libcurl implementation */

#include <curl/curl.h>
#include <stdlib.h>

typedef struct {
  unsigned char *buf;
  int32_t cap;
  int32_t len;
} curl_write_ctx;

static size_t curl_write_cb(char *ptr, size_t size, size_t nmemb, void *userdata) {
  curl_write_ctx *ctx = (curl_write_ctx *)userdata;
  size_t total = size * nmemb;
  size_t avail = (size_t)(ctx->cap - ctx->len - 1);
  if (total > avail) {
    if (avail > 0) {
      memcpy(ctx->buf + ctx->len, ptr, avail);
      ctx->len += (int32_t)avail;
    }
    return 0;  /* triggers CURLE_WRITE_ERROR */
  }
  memcpy(ctx->buf + ctx->len, ptr, total);
  ctx->len += (int32_t)total;
  return total;
}

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
) {
  int method_len = 0, url_len = 0, headers_len = 0, body_len = 0;
  char *method = moonbit_string_to_cstr(method_mbt, &method_len);
  char *url = moonbit_string_to_cstr(url_mbt, &url_len);
  char *headers_str = moonbit_string_to_cstr(headers_mbt, &headers_len);
  char *body = moonbit_string_to_cstr(body_mbt, &body_len);
  int resp_cap = Moonbit_array_length(resp_body_buf);

  write_meta(meta_buf, 0, 0);

  if (!url || !method) {
    write_error(error_buf, "string conversion failed");
    free(method); free(url); free(headers_str); free(body);
    return -1;
  }

  CURL *curl = curl_easy_init();
  if (!curl) {
    write_error(error_buf, "curl_easy_init failed");
    free(method); free(url); free(headers_str); free(body);
    return -1;
  }
  struct curl_slist *header_list = NULL;
  if (headers_len > 0) {
    char *hdr_copy = (char *)malloc((size_t)headers_len + 1);
    if (hdr_copy) {
      memcpy(hdr_copy, headers_str, (size_t)headers_len);
      hdr_copy[headers_len] = '\0';
      char *saveptr = NULL;
      char *line = strtok_r(hdr_copy, "\r\n", &saveptr);
      while (line) {
        if (strlen(line) > 0) header_list = curl_slist_append(header_list, line);
        line = strtok_r(NULL, "\r\n", &saveptr);
      }
      free(hdr_copy);
    }
  }

  curl_easy_setopt(curl, CURLOPT_URL, url);
  curl_easy_setopt(curl, CURLOPT_CUSTOMREQUEST, method);
  if (header_list) curl_easy_setopt(curl, CURLOPT_HTTPHEADER, header_list);
  if (body_len > 0) {
    curl_easy_setopt(curl, CURLOPT_POSTFIELDS, body);
    curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE, (long)body_len);
  } else {
    curl_easy_setopt(curl, CURLOPT_POSTFIELDS, "");
    curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE, 0L);
  }
  curl_easy_setopt(curl, CURLOPT_TIMEOUT_MS, (long)timeout_ms);
  curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT_MS, (long)(timeout_ms > 1000 ? timeout_ms / 2 : timeout_ms));
  curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);

  curl_write_ctx ctx = { .buf = resp_body_buf, .cap = resp_cap, .len = 0 };
  curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, curl_write_cb);
  curl_easy_setopt(curl, CURLOPT_WRITEDATA, &ctx);

  char curl_errbuf[CURL_ERROR_SIZE];
  curl_errbuf[0] = '\0';
  curl_easy_setopt(curl, CURLOPT_ERRORBUFFER, curl_errbuf);

  CURLcode res = curl_easy_perform(curl);

  if (res == CURLE_OK) {
    long http_code = 0;
    curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &http_code);
    resp_body_buf[ctx.len] = 0;
    write_meta(meta_buf, (int32_t)http_code, ctx.len);
  } else {
    resp_body_buf[0] = 0;
    write_meta(meta_buf, 0, 0);
    const char *emsg = (curl_errbuf[0] != '\0') ? curl_errbuf : curl_easy_strerror(res);
    write_error(error_buf, emsg);
  }

  if (header_list) curl_slist_free_all(header_list);
  curl_easy_cleanup(curl);
  free(method); free(url); free(headers_str); free(body);
  return (res == CURLE_OK) ? 0 : -1;
}

#endif

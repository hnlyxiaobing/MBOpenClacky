/*
 * HTTP Thread Offloading for MBOpenClacky.
 *
 * Spawns an OS thread to perform synchronous HTTP (WinHTTP/libcurl)
 * without blocking MoonBit's single-threaded async event loop.
 * The thread writes the result to a pipe file descriptor, which
 * MoonBit reads asynchronously via @pipe.PipeRead.
 *
 * Pipe data format (all little-endian):
 *   bytes [0..3]  = result flag  (0 = success, -1 = transport error)
 *   bytes [4..7]  = HTTP status  (0 if transport error)
 *   bytes [8..11] = body length  (bytes of body or error message)
 *   bytes [12..]  = body / error message (UTF-8)
 */

#include <moonbit.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

#include "http_thread.h"

#ifdef _WIN32
  #include <windows.h>
#else
  #include <unistd.h>
  #include <fcntl.h>
  #include <pthread.h>
#endif

/* ── MoonBit String -> C string conversion ─────────────────────── */

static char *mb_str_to_c(moonbit_string_t str, int *out_len) {
  int len = Moonbit_array_length(str);
  char *buf = (char *)malloc((size_t)len * 3 + 1);
  if (!buf) { if (out_len) *out_len = 0; return NULL; }
  int j = 0;
  for (int i = 0; i < len; i++) {
    uint16_t c = str[i];
    if (c < 0x80) {
      buf[j++] = (char)c;
    } else if (c < 0x800) {
      buf[j++] = (char)(0xC0 | (c >> 6));
      buf[j++] = (char)(0x80 | (c & 0x3F));
    } else {
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

static char *mb_strdup(const char *s) {
  int len = (int)strlen(s);
  char *p = (char *)malloc(len + 1);
  if (p) { memcpy(p, s, len); p[len] = 0; }
  return p;
}

/* ── Pipe write helpers ────────────────────────────────────────── */

static void write_all(int fd, const void *data, int len) {
  const char *p = (const char *)data;
  int remaining = len;
  while (remaining > 0) {
#ifdef _WIN32
    DWORD written = 0;
    if (!WriteFile((HANDLE)(intptr_t)fd, p, remaining, &written, NULL)) break;
    p += written;
    remaining -= (int)written;
#else
    ssize_t written = write(fd, p, remaining);
    if (written <= 0) break;
    p += written;
    remaining -= (int)written;
#endif
  }
}

static void write_le32(int fd, int32_t val) {
  unsigned char buf[4];
  buf[0] = (uint8_t)(val & 0xFF);
  buf[1] = (uint8_t)((val >> 8) & 0xFF);
  buf[2] = (uint8_t)((val >> 16) & 0xFF);
  buf[3] = (uint8_t)((val >> 24) & 0xFF);
  write_all(fd, buf, 4);
}

static void close_pipe_fd(int fd) {
#ifdef _WIN32
  CloseHandle((HANDLE)(intptr_t)fd);
#else
  close(fd);
#endif
}

static void set_blocking(int fd) {
#ifndef _WIN32
  int flags = fcntl(fd, F_GETFL, 0);
  if (flags >= 0) fcntl(fd, F_SETFL, flags & ~O_NONBLOCK);
#endif
}

/* ── Thread data ───────────────────────────────────────────────── */

typedef struct {
  char *method;
  char *url;
  char *headers;
  char *body;
  int body_len;
  int timeout_ms;
  int write_fd;
} http_thread_arg;

/* ── Platform HTTP implementation ─────────────────────────────── */

#ifdef _WIN32

#include <winhttp.h>
#pragma comment(lib, "winhttp.lib")

static void parse_url_win(
  const char *url,
  wchar_t *host, int host_cap,
  wchar_t *path, int path_cap,
  int *use_https, int *port
) {
  const char *p = url;
  *use_https = 1; *port = 443;
  if (strncmp(p, "https://", 8) == 0) p += 8;
  else if (strncmp(p, "http://", 7) == 0) { p += 7; *use_https = 0; *port = 80; }
  else { host[0] = 0; path[0] = '/'; path[1] = 0; return; }
  const char *path_sep = strchr(p, '/');
  int host_len = path_sep ? (int)(path_sep - p) : (int)strlen(p);
  const char *colon = NULL;
  for (int i = 0; i < host_len; i++) { if (p[i] == ':') { colon = &p[i]; break; } }
  if (colon) {
    int name_len = (int)(colon - p);
    if (name_len >= host_cap) name_len = host_cap - 1;
    MultiByteToWideChar(CP_UTF8, 0, p, name_len, host, host_cap);
    host[name_len] = 0;
    *port = atoi(colon + 1);
  } else {
    if (host_len >= host_cap) host_len = host_cap - 1;
    MultiByteToWideChar(CP_UTF8, 0, p, host_len, host, host_cap);
    host[host_len] = 0;
  }
  if (path_sep) {
    int plen = (int)strlen(path_sep);
    if (plen >= path_cap) plen = path_cap - 1;
    MultiByteToWideChar(CP_UTF8, 0, path_sep, plen, path, path_cap);
    path[plen] = 0;
  } else { path[0] = '/'; path[1] = 0; }
}

static void perform_http(
  http_thread_arg *arg, char *resp_buf, int resp_cap,
  int32_t *out_result, int32_t *out_status, int32_t *out_body_len,
  char *err_buf, int err_cap
) {
  *out_result = -1; *out_status = 0; *out_body_len = 0;
  wchar_t w_host[512], w_path[4096];
  int use_https, port;
  parse_url_win(arg->url, w_host, 512, w_path, 4096, &use_https, &port);

  HINTERNET session = WinHttpOpen(L"MBOpenClacky/0.1",
    WINHTTP_ACCESS_TYPE_DEFAULT_PROXY, WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
  if (!session) { snprintf(err_buf, err_cap, "WinHttpOpen failed"); return; }
  int ct = arg->timeout_ms > 10000 ? 10000 : arg->timeout_ms;
  WinHttpSetTimeouts(session, arg->timeout_ms, ct, arg->timeout_ms, arg->timeout_ms);

  HINTERNET connect = WinHttpConnect(session, w_host, (INTERNET_PORT)port, 0);
  if (!connect) { snprintf(err_buf, err_cap, "WinHttpConnect failed"); WinHttpCloseHandle(session); return; }

  wchar_t w_method[16];
  MultiByteToWideChar(CP_UTF8, 0, arg->method, -1, w_method, 16);
  DWORD flags = use_https ? WINHTTP_FLAG_SECURE : 0;
  HINTERNET request = WinHttpOpenRequest(connect, w_method, w_path, NULL,
    WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, flags);
  if (!request) { snprintf(err_buf, err_cap, "WinHttpOpenRequest failed"); WinHttpCloseHandle(connect); WinHttpCloseHandle(session); return; }

  if (arg->headers && arg->headers[0]) {
    wchar_t w_headers[16384];
    int hl = (int)strlen(arg->headers);
    int whl = MultiByteToWideChar(CP_UTF8, 0, arg->headers, hl, w_headers, 16380);
    if (whl > 0) { w_headers[whl] = 0; WinHttpAddRequestHeaders(request, w_headers, (ULONG)-1L, WINHTTP_ADDREQ_FLAG_ADD | WINHTTP_ADDREQ_FLAG_REPLACE); }
  }

  BOOL sent = WinHttpSendRequest(request, WINHTTP_NO_ADDITIONAL_HEADERS, 0,
    arg->body_len > 0 ? (LPVOID)arg->body : WINHTTP_NO_REQUEST_DATA,
    (DWORD)arg->body_len, 0, NULL);
  if (!sent) { snprintf(err_buf, err_cap, "WinHttpSendRequest failed"); goto win_done; }
  if (!WinHttpReceiveResponse(request, NULL)) { snprintf(err_buf, err_cap, "WinHttpReceiveResponse failed"); goto win_done; }

  {
    DWORD status_code = 0, status_size = sizeof(status_code);
    WinHttpQueryHeaders(request, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
      WINHTTP_HEADER_NAME_BY_INDEX, &status_code, &status_size, WINHTTP_NO_HEADER_INDEX);
    int32_t total = 0;
    for (;;) {
      DWORD avail = 0;
      if (!WinHttpQueryDataAvailable(request, &avail)) break;
      if (avail == 0) break;
      DWORD to_read = (DWORD)(resp_cap - total - 1);
      if (to_read > avail) to_read = avail;
      if (to_read == 0) break;
      DWORD got = 0;
      if (!WinHttpReadData(request, resp_buf + total, to_read, &got)) break;
      total += (int32_t)got;
      if (got == 0) break;
    }
    resp_buf[total] = 0;
    *out_result = 0; *out_status = (int32_t)status_code; *out_body_len = total;
  }
win_done:
  if (*out_result != 0) {
    snprintf(err_buf, err_cap, "WinHTTP error: 0x%08lX", GetLastError());
  }
  if (request) WinHttpCloseHandle(request);
  if (connect) WinHttpCloseHandle(connect);
  if (session) WinHttpCloseHandle(session);
}

#else /* Linux/macOS: libcurl */

#include <curl/curl.h>

typedef struct { unsigned char *buf; int cap; int len; } curl_ctx;

static size_t curl_write_cb(char *ptr, size_t size, size_t nmemb, void *ud) {
  curl_ctx *ctx = (curl_ctx *)ud;
  size_t total = size * nmemb;
  size_t avail = (size_t)(ctx->cap - ctx->len - 1);
  if (total > avail) {
    if (avail > 0) { memcpy(ctx->buf + ctx->len, ptr, avail); ctx->len += (int)avail; }
    return 0;
  }
  memcpy(ctx->buf + ctx->len, ptr, total);
  ctx->len += (int)total;
  return total;
}

static void perform_http(
  http_thread_arg *arg, char *resp_buf, int resp_cap,
  int32_t *out_result, int32_t *out_status, int32_t *out_body_len,
  char *err_buf, int err_cap
) {
  *out_result = -1; *out_status = 0; *out_body_len = 0;

  CURL *curl = curl_easy_init();
  if (!curl) { snprintf(err_buf, err_cap, "curl_easy_init failed"); return; }

  struct curl_slist *header_list = NULL;
  if (arg->headers && arg->headers[0]) {
    char *hdr_copy = (char *)malloc(strlen(arg->headers) + 1);
    if (hdr_copy) {
      strcpy(hdr_copy, arg->headers);
      char *saveptr = NULL;
      char *line = strtok_r(hdr_copy, "\r\n", &saveptr);
      while (line) {
        if (strlen(line) > 0) header_list = curl_slist_append(header_list, line);
        line = strtok_r(NULL, "\r\n", &saveptr);
      }
      free(hdr_copy);
    }
  }

  curl_easy_setopt(curl, CURLOPT_URL, arg->url);
  curl_easy_setopt(curl, CURLOPT_CUSTOMREQUEST, arg->method);
  if (header_list) curl_easy_setopt(curl, CURLOPT_HTTPHEADER, header_list);
  if (arg->body_len > 0) {
    curl_easy_setopt(curl, CURLOPT_POSTFIELDS, arg->body);
    curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE, (long)arg->body_len);
  } else {
    curl_easy_setopt(curl, CURLOPT_POSTFIELDS, "");
    curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE, 0L);
  }
  curl_easy_setopt(curl, CURLOPT_TIMEOUT_MS, (long)arg->timeout_ms);
  curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT_MS, (long)(arg->timeout_ms > 1000 ? arg->timeout_ms / 2 : arg->timeout_ms));
  curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);

  curl_ctx ctx = { .buf = (unsigned char *)resp_buf, .cap = resp_cap, .len = 0 };
  curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, curl_write_cb);
  curl_easy_setopt(curl, CURLOPT_WRITEDATA, &ctx);

  char curl_errbuf[CURL_ERROR_SIZE];
  curl_errbuf[0] = '\0';
  curl_easy_setopt(curl, CURLOPT_ERRORBUFFER, curl_errbuf);

  CURLcode res = curl_easy_perform(curl);
  if (res == CURLE_OK) {
    long http_code = 0;
    curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &http_code);
    resp_buf[ctx.len] = 0;
    *out_result = 0; *out_status = (int32_t)http_code; *out_body_len = ctx.len;
  } else {
    const char *emsg = (curl_errbuf[0] != '\0') ? curl_errbuf : curl_easy_strerror(res);
    snprintf(err_buf, err_cap, "%s", emsg);
  }

  if (header_list) curl_slist_free_all(header_list);
  curl_easy_cleanup(curl);
}

#endif

/* ── Thread function ───────────────────────────────────────────── */

#ifdef _WIN32
static DWORD WINAPI http_thread_proc(LPVOID param) {
#else
static void *http_thread_proc(void *param) {
#endif
  http_thread_arg *arg = (http_thread_arg *)param;
  set_blocking(arg->write_fd);

  int resp_cap = 4 * 1024 * 1024;
  char *resp_buf = (char *)malloc(resp_cap);
  char err_buf[1024];
  err_buf[0] = '\0';

  int32_t result, status, body_len;
  perform_http(arg, resp_buf, resp_cap, &result, &status, &body_len, err_buf, sizeof(err_buf));

  if (result == 0) {
    write_le32(arg->write_fd, 0);
    write_le32(arg->write_fd, status);
    write_le32(arg->write_fd, body_len);
    if (body_len > 0) write_all(arg->write_fd, resp_buf, body_len);
  } else {
    int err_len = (int)strlen(err_buf);
    write_le32(arg->write_fd, -1);
    write_le32(arg->write_fd, 0);
    write_le32(arg->write_fd, err_len);
    if (err_len > 0) write_all(arg->write_fd, err_buf, err_len);
  }

  close_pipe_fd(arg->write_fd);
  free(resp_buf);
  free(arg->method); free(arg->url); free(arg->headers); free(arg->body);
  free(arg);
  return 0;
}

/* ── FFI entry: start HTTP in background thread ─────────────────── */

MOONBIT_FFI_EXPORT
int32_t mbopenclacky_start_http_thread(
  moonbit_string_t method_mbt,
  moonbit_string_t url_mbt,
  moonbit_string_t headers_mbt,
  moonbit_string_t body_mbt,
  int32_t timeout_ms,
  int32_t write_fd
) {
  int m_len = 0, u_len = 0, h_len = 0, b_len = 0;
  char *method = mb_str_to_c(method_mbt, &m_len);
  char *url = mb_str_to_c(url_mbt, &u_len);
  char *headers = mb_str_to_c(headers_mbt, &h_len);
  char *body = mb_str_to_c(body_mbt, &b_len);

  if (!method || !url) {
    free(method); free(url); free(headers); free(body);
    return -1;
  }

  http_thread_arg *arg = (http_thread_arg *)malloc(sizeof(http_thread_arg));
  if (!arg) { free(method); free(url); free(headers); free(body); return -1; }
  arg->method = method;
  arg->url = url;
  arg->headers = headers ? headers : mb_strdup("");
  arg->body = body ? body : mb_strdup("");
  arg->body_len = b_len;
  arg->timeout_ms = timeout_ms;
  arg->write_fd = write_fd;

#ifdef _WIN32
  HANDLE h = CreateThread(NULL, 0, http_thread_proc, arg, 0, NULL);
  if (h) CloseHandle(h);
  else { free(arg->method); free(arg->url); free(arg->headers); free(arg->body); free(arg); return -1; }
#else
  pthread_t tid;
  if (pthread_create(&tid, NULL, http_thread_proc, arg) != 0) {
    free(arg->method); free(arg->url); free(arg->headers); free(arg->body); free(arg); return -1;
  }
  pthread_detach(tid);
#endif

  return 0;
}

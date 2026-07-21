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
    (DWORD)arg->body_len, (DWORD)arg->body_len, NULL);
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
    /* Append the OS error code to the specific failure message. */
    if (err_buf[0] != '\0') {
      int used = (int)strlen(err_buf);
      snprintf(err_buf + used, err_cap - used, " (0x%08lX)", GetLastError());
    } else {
      snprintf(err_buf, err_cap, "WinHTTP error: 0x%08lX", GetLastError());
    }
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
) {  int m_len = 0, u_len = 0, h_len = 0, b_len = 0;
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

/* ── Windows slot-based async HTTP ─────────────────────────────────
 *
 * Why slots instead of the pipe used on Unix: on Windows the pipe ends
 * handed out by moonbitlang/async are named-pipe HANDLEs registered with
 * the runtime's IOCP. Any overlapped write from our C thread would post a
 * completion packet to that IOCP, which the event loop would misinterpret
 * as one of its own job structures (crash). Synchronous writes on an
 * overlapped handle are undefined. So instead the worker thread stores
 * the result in a process-global slot and the MoonBit coroutine polls
 * the slot with @async.sleep between checks (the event loop stays free).
 */

#ifdef _WIN32

#define HTTP_SLOT_MAX 64

typedef struct {
  /* 0 = free, 1 = in-flight, 2 = done */
  volatile LONG state;
  int32_t result;      /* 0 = success, -1 = transport error */
  int32_t status;      /* HTTP status code (0 on transport error) */
  char *body;          /* malloc'd; response body or error message */
  int32_t body_len;
  int32_t abandoned;   /* MoonBit side cancelled; free when done */
  /* Streaming variant: growable buffer the worker appends chunks to. */
  char *stream_buf;
  int32_t stream_len;
  int32_t stream_cap;
  int32_t drain_pos;
} http_slot;

static http_slot g_http_slots[HTTP_SLOT_MAX];
static CRITICAL_SECTION g_http_slots_lock;
static int g_http_slots_ready = 0;

static void http_slots_lock(void) {
  if (!g_http_slots_ready) {
    /* Best-effort one-time init; racing inits are harmless because
       InitializeCriticalSection on zero-initialized memory is idempotent
       enough for our purpose, and all callers go through this function. */
    InitializeCriticalSection(&g_http_slots_lock);
    g_http_slots_ready = 1;
  }
  EnterCriticalSection(&g_http_slots_lock);
}

static void http_slots_unlock(void) {
  LeaveCriticalSection(&g_http_slots_lock);
}

typedef struct {
  int slot_id;
  char *method;
  char *url;
  char *headers;
  char *body;
  int body_len;
  int timeout_ms;
} http_slot_thread_arg;

static DWORD WINAPI http_slot_thread_proc(LPVOID param) {
  http_slot_thread_arg *arg = (http_slot_thread_arg *)param;

  int resp_cap = 4 * 1024 * 1024;
  char *resp_buf = (char *)malloc(resp_cap);
  char err_buf[1024];
  err_buf[0] = '\0';

  int32_t result = -1, status = 0, body_len = 0;
  if (resp_buf) {
    http_thread_arg ha;
    ha.method = arg->method;
    ha.url = arg->url;
    ha.headers = arg->headers;
    ha.body = arg->body;
    ha.body_len = arg->body_len;
    ha.timeout_ms = arg->timeout_ms;
    ha.write_fd = -1;
    perform_http(&ha, resp_buf, resp_cap, &result, &status, &body_len,
                 err_buf, sizeof(err_buf));
  } else {
    snprintf(err_buf, sizeof(err_buf), "out of memory");
  }

  const char *payload;
  int payload_len;
  if (result == 0) {
    payload = resp_buf;
    payload_len = body_len;
  } else {
    payload = err_buf;
    payload_len = (int)strlen(err_buf);
  }

  char *body_copy = (char *)malloc((size_t)payload_len + 1);
  if (body_copy) {
    memcpy(body_copy, payload, payload_len);
    body_copy[payload_len] = 0;
  }

  http_slots_lock();
  http_slot *slot = &g_http_slots[arg->slot_id];
  slot->result = result;
  slot->status = status;
  slot->body = body_copy;
  slot->body_len = body_copy ? payload_len : 0;
  slot->state = 2;
  if (slot->abandoned) {
    free(slot->body);
    slot->body = NULL;
    slot->body_len = 0;
    slot->abandoned = 0;
    slot->state = 0;
  }
  http_slots_unlock();

  free(resp_buf);
  free(arg->method);
  free(arg->url);
  free(arg->headers);
  free(arg->body);
  free(arg);
  return 0;
}

/* Start an HTTP request on a worker thread. Returns a slot id (>= 0)
   or -1 on failure. */
MOONBIT_FFI_EXPORT
int32_t mbopenclacky_http_start(
  moonbit_string_t method_mbt,
  moonbit_string_t url_mbt,
  moonbit_string_t headers_mbt,
  moonbit_string_t body_mbt,
  int32_t timeout_ms
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

  http_slots_lock();
  int slot_id = -1;
  for (int i = 0; i < HTTP_SLOT_MAX; i++) {
    if (g_http_slots[i].state == 0) {
      g_http_slots[i].state = 1;
      g_http_slots[i].result = -1;
      g_http_slots[i].status = 0;
      g_http_slots[i].body = NULL;
      g_http_slots[i].body_len = 0;
      g_http_slots[i].abandoned = 0;
      g_http_slots[i].stream_buf = NULL;
      g_http_slots[i].stream_len = 0;
      g_http_slots[i].stream_cap = 0;
      g_http_slots[i].drain_pos = 0;
      slot_id = i;
      break;
    }
  }
  http_slots_unlock();
  if (slot_id < 0) {
    free(method); free(url); free(headers); free(body);
    return -1;
  }

  http_slot_thread_arg *arg =
    (http_slot_thread_arg *)malloc(sizeof(http_slot_thread_arg));
  if (!arg) {
    http_slots_lock();
    g_http_slots[slot_id].state = 0;
    http_slots_unlock();
    free(method); free(url); free(headers); free(body);
    return -1;
  }
  arg->slot_id = slot_id;
  arg->method = method;
  arg->url = url;
  arg->headers = headers ? headers : mb_strdup("");
  arg->body = body ? body : mb_strdup("");
  arg->body_len = b_len;
  arg->timeout_ms = timeout_ms;

  HANDLE h = CreateThread(NULL, 0, http_slot_thread_proc, arg, 0, NULL);
  if (h) {
    CloseHandle(h);
  } else {
    http_slots_lock();
    g_http_slots[slot_id].state = 0;
    http_slots_unlock();
    free(arg->method); free(arg->url); free(arg->headers); free(arg->body);
    free(arg);
    return -1;
  }
  return slot_id;
}

/* Poll a request slot: 0 = pending, 1 = done, -1 = invalid id. */
MOONBIT_FFI_EXPORT
int32_t mbopenclacky_http_poll(int32_t slot_id) {
  if (slot_id < 0 || slot_id >= HTTP_SLOT_MAX) return -1;
  http_slots_lock();
  LONG state = g_http_slots[slot_id].state;
  http_slots_unlock();
  if (state == 0) return -1;
  return state == 2 ? 1 : 0;
}

/* Result status for a completed slot: HTTP status code, or -1 for
   transport error. Call only after poll reports done. */
MOONBIT_FFI_EXPORT
int32_t mbopenclacky_http_result_status(int32_t slot_id) {
  if (slot_id < 0 || slot_id >= HTTP_SLOT_MAX) return -1;
  http_slots_lock();
  http_slot *slot = &g_http_slots[slot_id];
  int32_t status = slot->result == 0 ? slot->status : -1;
  http_slots_unlock();
  return status;
}

/* Fetch the body (or error message) of a completed slot as a MoonBit
   string (lossy UTF-8 -> UTF-16), then free the slot for reuse.
   Call only after poll reports done. */
MOONBIT_FFI_EXPORT
moonbit_string_t mbopenclacky_http_result_body(int32_t slot_id) {
  if (slot_id < 0 || slot_id >= HTTP_SLOT_MAX) {
    return moonbit_make_string_raw(0);
  }
  http_slots_lock();
  http_slot *slot = &g_http_slots[slot_id];
  char *body = slot->body;
  int32_t body_len = slot->body_len;
  /* Detach and free the slot. */
  slot->body = NULL;
  slot->body_len = 0;
  free(slot->stream_buf);
  slot->stream_buf = NULL;
  slot->stream_len = 0;
  slot->stream_cap = 0;
  slot->drain_pos = 0;
  slot->state = 0;
  http_slots_unlock();

  if (!body || body_len <= 0) {
    free(body);
    return moonbit_make_string_raw(0);
  }
  int wlen = MultiByteToWideChar(CP_UTF8, 0, body, body_len, NULL, 0);
  if (wlen <= 0) {
    free(body);
    return moonbit_make_string_raw(0);
  }
  moonbit_string_t result = moonbit_make_string_raw(wlen);
  if (!result) {
    free(body);
    return moonbit_make_string_raw(0);
  }
  MultiByteToWideChar(CP_UTF8, 0, body, body_len, result, wlen);
  free(body);
  return result;
}

/* Abandon a request (e.g. the coroutine was cancelled). The worker
   thread keeps running and frees the slot when it finishes. If the
   request already completed, the slot is freed immediately. */
MOONBIT_FFI_EXPORT
void mbopenclacky_http_abandon(int32_t slot_id) {
  if (slot_id < 0 || slot_id >= HTTP_SLOT_MAX) return;
  http_slots_lock();
  http_slot *slot = &g_http_slots[slot_id];
  if (slot->state == 2) {
    free(slot->body);
    slot->body = NULL;
    slot->body_len = 0;
    free(slot->stream_buf);
    slot->stream_buf = NULL;
    slot->stream_len = 0;
    slot->stream_cap = 0;
    slot->drain_pos = 0;
    slot->state = 0;
  } else if (slot->state == 1) {
    slot->abandoned = 1;
  }
  http_slots_unlock();
}

#endif /* _WIN32 */

/* ── Streaming HTTP ────────────────────────────────────────────────
 *
 * Unlike the buffered request above, the streaming variant forwards the
 * response body to MoonBit INCREMENTALLY so SSE frames can be surfaced
 * token-by-token.
 *
 * Unix: the curl write callback pushes length-prefixed frames onto the
 * pipe as data arrives:
 *   [4B LE len][len bytes]   repeated data chunks (raw response bytes)
 *   [4B LE 0]                end-of-stream marker
 *   [4B result][4B status]   trailer (result: 0 ok / -1 transport error)
 * On transport error the error message is sent as one final data chunk.
 *
 * Windows: same slot mechanism as the buffered path, plus a growable
 * stream buffer the worker thread appends to under the slot lock; the
 * MoonBit coroutine drains new bytes between polls.
 */

#ifndef _WIN32

typedef struct {
  int fd;
} stream_cb_ctx;

static size_t stream_write_cb(char *ptr, size_t size, size_t nmemb, void *ud) {
  stream_cb_ctx *ctx = (stream_cb_ctx *)ud;
  size_t total = size * nmemb;
  if (total == 0) return 0;
  write_le32(ctx->fd, (int32_t)total);
  write_all(ctx->fd, ptr, (int)total);
  return total;
}

static void *http_stream_thread_proc(void *param) {
  http_thread_arg *arg = (http_thread_arg *)param;
  set_blocking(arg->write_fd);

  int32_t result = -1, status = 0;
  char err_buf[1024];
  err_buf[0] = '\0';

  CURL *curl = curl_easy_init();
  if (!curl) {
    snprintf(err_buf, sizeof(err_buf), "curl_easy_init failed");
  } else {
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
    curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT_MS,
      (long)(arg->timeout_ms > 1000 ? arg->timeout_ms / 2 : arg->timeout_ms));
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);

    stream_cb_ctx ctx = { .fd = arg->write_fd };
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, stream_write_cb);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &ctx);

    char curl_errbuf[CURL_ERROR_SIZE];
    curl_errbuf[0] = '\0';
    curl_easy_setopt(curl, CURLOPT_ERRORBUFFER, curl_errbuf);

    CURLcode res = curl_easy_perform(curl);
    if (res == CURLE_OK) {
      long http_code = 0;
      curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &http_code);
      result = 0;
      status = (int32_t)http_code;
    } else {
      const char *emsg = (curl_errbuf[0] != '\0') ? curl_errbuf : curl_easy_strerror(res);
      snprintf(err_buf, sizeof(err_buf), "%s", emsg);
    }

    if (header_list) curl_slist_free_all(header_list);
    curl_easy_cleanup(curl);
  }

  if (result != 0) {
    /* Deliver the error message as one final data chunk. */
    int err_len = (int)strlen(err_buf);
    write_le32(arg->write_fd, err_len);
    if (err_len > 0) write_all(arg->write_fd, err_buf, err_len);
  }
  /* End-of-stream marker + trailer. */
  write_le32(arg->write_fd, 0);
  write_le32(arg->write_fd, result);
  write_le32(arg->write_fd, status);

  close_pipe_fd(arg->write_fd);
  free(arg->method); free(arg->url); free(arg->headers); free(arg->body);
  free(arg);
  return NULL;
}

/* Start a STREAMING HTTP request on a background thread (Unix).
   Same arguments as mbopenclacky_start_http_thread; pipe protocol is the
   frame format documented above. */
MOONBIT_FFI_EXPORT
int32_t mbopenclacky_start_http_stream_thread(
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

  pthread_t tid;
  if (pthread_create(&tid, NULL, http_stream_thread_proc, arg) != 0) {
    free(arg->method); free(arg->url); free(arg->headers); free(arg->body);
    free(arg);
    return -1;
  }
  pthread_detach(tid);
  return 0;
}

#endif /* !_WIN32 */

#ifdef _WIN32

/* ── Windows streaming slots ─────────────────────────────────────── */

/* Append bytes to a slot's stream buffer (called from the worker thread). */
static void slot_stream_append(int slot_id, const char *data, int len) {
  if (len <= 0) return;
  http_slots_lock();
  http_slot *slot = &g_http_slots[slot_id];
  if (slot->state == 1) {
    if (slot->stream_len + len > slot->stream_cap) {
      int new_cap = slot->stream_cap > 0 ? slot->stream_cap : 16384;
      while (new_cap < slot->stream_len + len) new_cap *= 2;
      char *nb = (char *)realloc(slot->stream_buf, (size_t)new_cap);
      if (nb) {
        slot->stream_buf = nb;
        slot->stream_cap = new_cap;
      }
    }
    if (slot->stream_buf && slot->stream_len + len <= slot->stream_cap) {
      memcpy(slot->stream_buf + slot->stream_len, data, len);
      slot->stream_len += len;
    }
  }
  http_slots_unlock();
}

/* Length of the longest prefix of p[0..len) that ends on a complete
   UTF-8 character boundary. */
static int utf8_complete_prefix_len(const char *p, int len) {
  int i = 0;
  while (i < len) {
    unsigned char c = (unsigned char)p[i];
    int n;
    if (c < 0x80) n = 1;
    else if (c >= 0xC2 && c < 0xE0) n = 2;
    else if (c >= 0xE0 && c < 0xF0) n = 3;
    else if (c >= 0xF0 && c <= 0xF4) n = 4;
    else n = 1; /* invalid lead byte: consume singly (lossy) */
    if (i + n > len) break;
    int ok = 1;
    for (int k = 1; k < n; k++) {
      if (((unsigned char)p[i + k] & 0xC0) != 0x80) { ok = 0; break; }
    }
    if (!ok) n = 1;
    i += n;
  }
  return i;
}

/* WinHTTP request that streams each received chunk into the slot. */
static void perform_http_win_stream(
  http_thread_arg *arg, int slot_id,
  int32_t *out_result, int32_t *out_status,
  char *err_buf, int err_cap
) {
  *out_result = -1; *out_status = 0;
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
    (DWORD)arg->body_len, (DWORD)arg->body_len, NULL);
  if (!sent) { snprintf(err_buf, err_cap, "WinHttpSendRequest failed"); goto win_stream_done; }
  if (!WinHttpReceiveResponse(request, NULL)) { snprintf(err_buf, err_cap, "WinHttpReceiveResponse failed"); goto win_stream_done; }

  {
    DWORD status_code = 0, status_size = sizeof(status_code);
    WinHttpQueryHeaders(request, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
      WINHTTP_HEADER_NAME_BY_INDEX, &status_code, &status_size, WINHTTP_NO_HEADER_INDEX);
    char chunk[16384];
    for (;;) {
      DWORD avail = 0;
      if (!WinHttpQueryDataAvailable(request, &avail)) break;
      if (avail == 0) break;
      DWORD to_read = avail > sizeof(chunk) ? sizeof(chunk) : avail;
      DWORD got = 0;
      if (!WinHttpReadData(request, chunk, to_read, &got)) break;
      if (got == 0) break;
      slot_stream_append(slot_id, chunk, (int)got);
    }
    *out_result = 0; *out_status = (int32_t)status_code;
  }
win_stream_done:
  if (*out_result != 0) {
    /* Append the OS error code to the specific failure message. */
    if (err_buf[0] != '\0') {
      int used = (int)strlen(err_buf);
      snprintf(err_buf + used, err_cap - used, " (0x%08lX)", GetLastError());
    } else {
      snprintf(err_buf, err_cap, "WinHTTP error: 0x%08lX", GetLastError());
    }
  }
  if (request) WinHttpCloseHandle(request);
  if (connect) WinHttpCloseHandle(connect);
  if (session) WinHttpCloseHandle(session);
}

static DWORD WINAPI http_stream_slot_thread_proc(LPVOID param) {
  http_slot_thread_arg *arg = (http_slot_thread_arg *)param;

  char err_buf[1024];
  err_buf[0] = '\0';
  int32_t result = -1, status = 0;

  http_thread_arg ha;
  ha.method = arg->method;
  ha.url = arg->url;
  ha.headers = arg->headers;
  ha.body = arg->body;
  ha.body_len = arg->body_len;
  ha.timeout_ms = arg->timeout_ms;
  ha.write_fd = -1;
  perform_http_win_stream(&ha, arg->slot_id, &result, &status, err_buf, sizeof(err_buf));

  http_slots_lock();
  http_slot *slot = &g_http_slots[arg->slot_id];
  slot->result = result;
  slot->status = status;
  if (result != 0) {
    slot->body = mb_strdup(err_buf);
    slot->body_len = (int32_t)strlen(err_buf);
  }
  slot->state = 2;
  if (slot->abandoned) {
    free(slot->body);
    slot->body = NULL;
    slot->body_len = 0;
    free(slot->stream_buf);
    slot->stream_buf = NULL;
    slot->stream_len = 0;
    slot->stream_cap = 0;
    slot->drain_pos = 0;
    slot->abandoned = 0;
    slot->state = 0;
  }
  http_slots_unlock();

  free(arg->method); free(arg->url); free(arg->headers); free(arg->body);
  free(arg);
  return 0;
}

/* Start a STREAMING HTTP request on a worker thread. Returns a slot id
   (>= 0) or -1 on failure. Drain incremental bytes with
   mbopenclacky_http_stream_drain; completion/status/error handling is the
   same as the buffered slot API. */
MOONBIT_FFI_EXPORT
int32_t mbopenclacky_http_stream_start(
  moonbit_string_t method_mbt,
  moonbit_string_t url_mbt,
  moonbit_string_t headers_mbt,
  moonbit_string_t body_mbt,
  int32_t timeout_ms
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

  http_slots_lock();
  int slot_id = -1;
  for (int i = 0; i < HTTP_SLOT_MAX; i++) {
    if (g_http_slots[i].state == 0) {
      g_http_slots[i].state = 1;
      g_http_slots[i].result = -1;
      g_http_slots[i].status = 0;
      g_http_slots[i].body = NULL;
      g_http_slots[i].body_len = 0;
      g_http_slots[i].abandoned = 0;
      g_http_slots[i].stream_buf = NULL;
      g_http_slots[i].stream_len = 0;
      g_http_slots[i].stream_cap = 0;
      g_http_slots[i].drain_pos = 0;
      slot_id = i;
      break;
    }
  }
  http_slots_unlock();
  if (slot_id < 0) {
    free(method); free(url); free(headers); free(body);
    return -1;
  }

  http_slot_thread_arg *arg =
    (http_slot_thread_arg *)malloc(sizeof(http_slot_thread_arg));
  if (!arg) {
    http_slots_lock();
    g_http_slots[slot_id].state = 0;
    http_slots_unlock();
    free(method); free(url); free(headers); free(body);
    return -1;
  }
  arg->slot_id = slot_id;
  arg->method = method;
  arg->url = url;
  arg->headers = headers ? headers : mb_strdup("");
  arg->body = body ? body : mb_strdup("");
  arg->body_len = b_len;
  arg->timeout_ms = timeout_ms;

  HANDLE h = CreateThread(NULL, 0, http_stream_slot_thread_proc, arg, 0, NULL);
  if (h) {
    CloseHandle(h);
  } else {
    http_slots_lock();
    g_http_slots[slot_id].state = 0;
    http_slots_unlock();
    free(arg->method); free(arg->url); free(arg->headers); free(arg->body);
    free(arg);
    return -1;
  }
  return slot_id;
}

/* Drain newly appended stream bytes from a slot as a MoonBit string.
   Only complete UTF-8 characters are returned; an incomplete trailing
   sequence stays buffered for the next drain. */
MOONBIT_FFI_EXPORT
moonbit_string_t mbopenclacky_http_stream_drain(int32_t slot_id) {
  if (slot_id < 0 || slot_id >= HTTP_SLOT_MAX) {
    return moonbit_make_string_raw(0);
  }
  http_slots_lock();
  http_slot *slot = &g_http_slots[slot_id];
  int avail = slot->stream_len - slot->drain_pos;
  if (avail <= 0 || !slot->stream_buf) {
    http_slots_unlock();
    return moonbit_make_string_raw(0);
  }
  int valid = utf8_complete_prefix_len(slot->stream_buf + slot->drain_pos, avail);
  if (valid <= 0) {
    http_slots_unlock();
    return moonbit_make_string_raw(0);
  }
  int wlen = MultiByteToWideChar(CP_UTF8, 0, slot->stream_buf + slot->drain_pos, valid, NULL, 0);
  moonbit_string_t result = wlen > 0 ? moonbit_make_string_raw(wlen) : NULL;
  if (result) {
    MultiByteToWideChar(CP_UTF8, 0, slot->stream_buf + slot->drain_pos, valid, result, wlen);
  }
  slot->drain_pos += valid;
  /* Compact the buffer once fully drained to bound memory. */
  if (slot->drain_pos == slot->stream_len) {
    slot->stream_len = 0;
    slot->drain_pos = 0;
  }
  http_slots_unlock();
  return result ? result : moonbit_make_string_raw(0);
}

#endif /* _WIN32 (streaming) */

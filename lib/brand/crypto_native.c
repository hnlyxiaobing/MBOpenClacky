#include <moonbit.h>
#include <stdint.h>
#include <string.h>

/* Helper: write status and body_size into meta_buf (little-endian) */
static void brand_write_meta(
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
static void brand_write_error(moonbit_bytes_t error_buf, const char *msg) {
  int elen = (int)strlen(msg);
  int cap = Moonbit_array_length(error_buf);
  if (elen > cap - 1) elen = cap - 1;
  memcpy(error_buf, msg, (size_t)elen);
  error_buf[elen] = 0;
}

/*
 * Convert MoonBit String (UTF-16) to null-terminated UTF-8 C string.
 * Returns malloc'd buffer; caller must free.
 */
static char *brand_mbt_string_to_cstr(moonbit_string_t str, int *out_len) {
  int len = Moonbit_array_length(str);
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
// Windows CNG implementation
#include <windows.h>
#include <bcrypt.h>
#pragma comment(lib, "bcrypt.lib")

#define NT_SUCCESS(Status) (((NTSTATUS)(Status)) >= 0)

MOONBIT_FFI_EXPORT
int32_t mbopenclacky_crypto_random_bytes(moonbit_bytes_t out) {
  int32_t len = Moonbit_array_length(out);
  NTSTATUS status = BCryptGenRandom(NULL, out, (ULONG)len, BCRYPT_USE_SYSTEM_PREFERRED_RNG);
  return NT_SUCCESS(status) ? 0 : -1;
}

/* ── Brand HTTP GET (Windows / WinHTTP) ────────────────────────────────────── */

#include <winhttp.h>
#pragma comment(lib, "winhttp.lib")

static int brand_parse_url(
  const char *url, wchar_t *host, int host_cap,
  wchar_t *path, int path_cap, int *use_https, int *port
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
    int plen = (int)strlen(path_sep);
    if (plen >= path_cap) return -1;
    MultiByteToWideChar(CP_UTF8, 0, path_sep, plen, path, path_cap);
    path[plen] = 0;
  } else {
    path[0] = '/';
    path[1] = 0;
  }
  return 0;
}

MOONBIT_FFI_EXPORT
int32_t mbopenclacky_brand_http_get(
  moonbit_string_t url_mbt,
  int32_t timeout_ms,
  moonbit_bytes_t resp_buf,
  moonbit_bytes_t meta_buf,
  moonbit_bytes_t error_buf
) {
  int32_t result = -1;
  int url_len = 0;
  char *url = brand_mbt_string_to_cstr(url_mbt, &url_len);
  int resp_cap = Moonbit_array_length(resp_buf);
  HINTERNET session = NULL, connect = NULL, request = NULL;
  wchar_t w_host[512], w_path[4096];
  int use_https, port;

  brand_write_meta(meta_buf, 0, 0);
  if (!url) {
    brand_write_error(error_buf, "string conversion failed");
    goto win_http_done;
  }
  if (brand_parse_url(url, w_host, 512, w_path, 4096, &use_https, &port) != 0) {
    brand_write_error(error_buf, "invalid URL");
    goto win_http_done;
  }
  session = WinHttpOpen(L"MBOpenClacky-Brand/0.1",
    WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
    WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
  if (!session) { brand_write_error(error_buf, "WinHttpOpen failed"); goto win_http_done; }
  int ct = timeout_ms > 10000 ? 10000 : timeout_ms;
  WinHttpSetTimeouts(session, timeout_ms, ct, timeout_ms, timeout_ms);
  connect = WinHttpConnect(session, w_host, (INTERNET_PORT)port, 0);
  if (!connect) goto win_http_done;
  DWORD flags = use_https ? WINHTTP_FLAG_SECURE : 0;
  request = WinHttpOpenRequest(connect, L"GET", w_path,
    NULL, WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, flags);
  if (!request) goto win_http_done;
  if (!WinHttpSendRequest(request, WINHTTP_NO_ADDITIONAL_HEADERS, 0,
      WINHTTP_NO_REQUEST_DATA, 0, 0, NULL)) goto win_http_done;
  if (!WinHttpReceiveResponse(request, NULL)) goto win_http_done;
  DWORD status_code = 0, status_size = sizeof(status_code);
  WinHttpQueryHeaders(request,
    WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
    WINHTTP_HEADER_NAME_BY_INDEX, &status_code, &status_size,
    WINHTTP_NO_HEADER_INDEX);
  int32_t total_read = 0;
  for (;;) {
    DWORD avail = 0;
    if (!WinHttpQueryDataAvailable(request, &avail)) break;
    if (avail == 0) break;
    DWORD to_read = (DWORD)(resp_cap - total_read - 1);
    if (to_read > avail) to_read = avail;
    if (to_read == 0) break;
    DWORD got = 0;
    if (!WinHttpReadData(request, resp_buf + total_read, to_read, &got)) break;
    total_read += (int32_t)got;
    if (got == 0) break;
  }
  resp_buf[total_read] = 0;
  brand_write_meta(meta_buf, (int32_t)status_code, total_read);
  result = 0;
win_http_done:
  if (result != 0) {
    char errbuf[256];
    snprintf(errbuf, sizeof(errbuf), "WinHTTP error: 0x%08lX", GetLastError());
    brand_write_error(error_buf, errbuf);
  }
  if (request) WinHttpCloseHandle(request);
  if (connect) WinHttpCloseHandle(connect);
  if (session) WinHttpCloseHandle(session);
  free(url);
  return result;
}

MOONBIT_FFI_EXPORT
int32_t mbopenclacky_aes256gcm_encrypt(
  moonbit_bytes_t key,
  moonbit_bytes_t nonce,
  moonbit_bytes_t aad,
  moonbit_bytes_t plaintext,
  moonbit_bytes_t ciphertext_out,
  moonbit_bytes_t tag_out
) {
  BCRYPT_ALG_HANDLE hAlg = NULL;
  BCRYPT_KEY_HANDLE hKey = NULL;
  NTSTATUS status;
  int32_t result = -1;

  status = BCryptOpenAlgorithmProvider(&hAlg, BCRYPT_AES_ALGORITHM, NULL, 0);
  if (!NT_SUCCESS(status)) return -1;

  status = BCryptSetProperty(hAlg, BCRYPT_CHAINING_MODE,
    (PUCHAR)BCRYPT_CHAIN_MODE_GCM, sizeof(BCRYPT_CHAIN_MODE_GCM), 0);
  if (!NT_SUCCESS(status)) goto cleanup;

  int32_t key_len = Moonbit_array_length(key);
  status = BCryptGenerateSymmetricKey(hAlg, &hKey, NULL, 0, key, (ULONG)key_len, 0);
  if (!NT_SUCCESS(status)) goto cleanup;

  int32_t nonce_len = Moonbit_array_length(nonce);
  int32_t aad_len = Moonbit_array_length(aad);
  int32_t pt_len = Moonbit_array_length(plaintext);
  int32_t tag_len = Moonbit_array_length(tag_out);

  BCRYPT_AUTHENTICATED_CIPHER_MODE_INFO authInfo;
  BCRYPT_INIT_AUTH_MODE_INFO(authInfo);
  authInfo.pbNonce = nonce;
  authInfo.cbNonce = (ULONG)nonce_len;
  authInfo.pbAuthData = aad_len > 0 ? aad : NULL;
  authInfo.cbAuthData = aad_len > 0 ? (ULONG)aad_len : 0;
  authInfo.pbTag = tag_out;
  authInfo.cbTag = (ULONG)tag_len;

  ULONG cbResult = 0;
  status = BCryptEncrypt(hKey, plaintext, (ULONG)pt_len, &authInfo,
    NULL, 0, ciphertext_out, (ULONG)pt_len, &cbResult, 0);

  if (NT_SUCCESS(status)) {
    result = 0;
  }

cleanup:
  if (hKey) BCryptDestroyKey(hKey);
  if (hAlg) BCryptCloseAlgorithmProvider(hAlg, 0);
  return result;
}

MOONBIT_FFI_EXPORT
int32_t mbopenclacky_aes256gcm_decrypt(
  moonbit_bytes_t key,
  moonbit_bytes_t nonce,
  moonbit_bytes_t aad,
  moonbit_bytes_t ciphertext,
  moonbit_bytes_t tag,
  moonbit_bytes_t plaintext_out
) {
  BCRYPT_ALG_HANDLE hAlg = NULL;
  BCRYPT_KEY_HANDLE hKey = NULL;
  NTSTATUS status;
  int32_t result = -1;

  status = BCryptOpenAlgorithmProvider(&hAlg, BCRYPT_AES_ALGORITHM, NULL, 0);
  if (!NT_SUCCESS(status)) return -1;

  status = BCryptSetProperty(hAlg, BCRYPT_CHAINING_MODE,
    (PUCHAR)BCRYPT_CHAIN_MODE_GCM, sizeof(BCRYPT_CHAIN_MODE_GCM), 0);
  if (!NT_SUCCESS(status)) goto cleanup;

  int32_t key_len = Moonbit_array_length(key);
  status = BCryptGenerateSymmetricKey(hAlg, &hKey, NULL, 0, key, (ULONG)key_len, 0);
  if (!NT_SUCCESS(status)) goto cleanup;

  int32_t nonce_len = Moonbit_array_length(nonce);
  int32_t aad_len = Moonbit_array_length(aad);
  int32_t ct_len = Moonbit_array_length(ciphertext);
  int32_t tag_len = Moonbit_array_length(tag);

  BCRYPT_AUTHENTICATED_CIPHER_MODE_INFO authInfo;
  BCRYPT_INIT_AUTH_MODE_INFO(authInfo);
  authInfo.pbNonce = nonce;
  authInfo.cbNonce = (ULONG)nonce_len;
  authInfo.pbAuthData = aad_len > 0 ? aad : NULL;
  authInfo.cbAuthData = aad_len > 0 ? (ULONG)aad_len : 0;
  authInfo.pbTag = tag;
  authInfo.cbTag = (ULONG)tag_len;

  ULONG cbResult = 0;
  status = BCryptDecrypt(hKey, ciphertext, (ULONG)ct_len, &authInfo,
    NULL, 0, plaintext_out, (ULONG)ct_len, &cbResult, 0);

  if (NT_SUCCESS(status)) {
    result = 0;
  }

cleanup:
  if (hKey) BCryptDestroyKey(hKey);
  if (hAlg) BCryptCloseAlgorithmProvider(hAlg, 0);
  return result;
}

#else
// Linux/macOS OpenSSL implementation
#include <openssl/evp.h>
#include <openssl/rand.h>
#include <openssl/err.h>

MOONBIT_FFI_EXPORT
int32_t mbopenclacky_crypto_random_bytes(moonbit_bytes_t out) {
  int32_t len = Moonbit_array_length(out);
  return RAND_bytes(out, len) == 1 ? 0 : -1;
}

/* ── Brand HTTP GET (Linux/macOS / libcurl) ─────────────────────────────────── */

#include <curl/curl.h>
#include <stdlib.h>

typedef struct {
  unsigned char *buf;
  int32_t cap;
  int32_t len;
} brand_curl_write_ctx;

static size_t brand_curl_write_cb(char *ptr, size_t size, size_t nmemb, void *userdata) {
  brand_curl_write_ctx *ctx = (brand_curl_write_ctx *)userdata;
  size_t total = size * nmemb;
  size_t avail = (size_t)(ctx->cap - ctx->len - 1);
  if (total > avail) {
    if (avail > 0) {
      memcpy(ctx->buf + ctx->len, ptr, avail);
      ctx->len += (int32_t)avail;
    }
    return 0;
  }
  memcpy(ctx->buf + ctx->len, ptr, total);
  ctx->len += (int32_t)total;
  return total;
}

MOONBIT_FFI_EXPORT
int32_t mbopenclacky_brand_http_get(
  moonbit_string_t url_mbt,
  int32_t timeout_ms,
  moonbit_bytes_t resp_buf,
  moonbit_bytes_t meta_buf,
  moonbit_bytes_t error_buf
) {
  int url_len = 0;
  char *url = brand_mbt_string_to_cstr(url_mbt, &url_len);
  int resp_cap = Moonbit_array_length(resp_buf);
  brand_write_meta(meta_buf, 0, 0);
  if (!url) {
    brand_write_error(error_buf, "string conversion failed");
    return -1;
  }
  CURL *curl = curl_easy_init();
  if (!curl) {
    brand_write_error(error_buf, "curl_easy_init failed");
    free(url);
    return -1;
  }
  curl_easy_setopt(curl, CURLOPT_URL, url);
  curl_easy_setopt(curl, CURLOPT_HTTPGET, 1L);
  curl_easy_setopt(curl, CURLOPT_TIMEOUT_MS, (long)timeout_ms);
  curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT_MS,
    (long)(timeout_ms > 1000 ? timeout_ms / 2 : timeout_ms));
  curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
  brand_curl_write_ctx ctx = { .buf = resp_buf, .cap = resp_cap, .len = 0 };
  curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, brand_curl_write_cb);
  curl_easy_setopt(curl, CURLOPT_WRITEDATA, &ctx);
  char curl_errbuf[CURL_ERROR_SIZE];
  curl_errbuf[0] = '\0';
  curl_easy_setopt(curl, CURLOPT_ERRORBUFFER, curl_errbuf);
  CURLcode res = curl_easy_perform(curl);
  int32_t result = -1;
  if (res == CURLE_OK) {
    long http_code = 0;
    curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &http_code);
    resp_buf[ctx.len] = 0;
    brand_write_meta(meta_buf, (int32_t)http_code, ctx.len);
    result = 0;
  } else {
    resp_buf[0] = 0;
    brand_write_meta(meta_buf, 0, 0);
    const char *emsg = (curl_errbuf[0] != '\0') ? curl_errbuf : curl_easy_strerror(res);
    brand_write_error(error_buf, emsg);
  }
  curl_easy_cleanup(curl);
  free(url);
  return result;
}

MOONBIT_FFI_EXPORT
int32_t mbopenclacky_aes256gcm_encrypt(
  moonbit_bytes_t key,
  moonbit_bytes_t nonce,
  moonbit_bytes_t aad,
  moonbit_bytes_t plaintext,
  moonbit_bytes_t ciphertext_out,
  moonbit_bytes_t tag_out
) {
  EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
  if (!ctx) return -1;

  int32_t result = -1;
  int len = 0;

  int32_t nonce_len = Moonbit_array_length(nonce);
  int32_t aad_len = Moonbit_array_length(aad);
  int32_t pt_len = Moonbit_array_length(plaintext);
  int32_t tag_len = Moonbit_array_length(tag_out);

  if (!EVP_EncryptInit_ex(ctx, EVP_aes_256_gcm(), NULL, NULL, NULL)) goto cleanup;
  if (!EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, nonce_len, NULL)) goto cleanup;
  if (!EVP_EncryptInit_ex(ctx, NULL, NULL, key, nonce)) goto cleanup;

  if (aad_len > 0) {
    if (!EVP_EncryptUpdate(ctx, NULL, &len, aad, aad_len)) goto cleanup;
  }

  if (!EVP_EncryptUpdate(ctx, ciphertext_out, &len, plaintext, pt_len)) goto cleanup;
  if (!EVP_EncryptFinal_ex(ctx, ciphertext_out + len, &len)) goto cleanup;
  if (!EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_GET_TAG, tag_len, tag_out)) goto cleanup;

  result = 0;

cleanup:
  EVP_CIPHER_CTX_free(ctx);
  return result;
}

MOONBIT_FFI_EXPORT
int32_t mbopenclacky_aes256gcm_decrypt(
  moonbit_bytes_t key,
  moonbit_bytes_t nonce,
  moonbit_bytes_t aad,
  moonbit_bytes_t ciphertext,
  moonbit_bytes_t tag,
  moonbit_bytes_t plaintext_out
) {
  EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
  if (!ctx) return -1;

  int32_t result = -1;
  int len = 0;

  int32_t nonce_len = Moonbit_array_length(nonce);
  int32_t aad_len = Moonbit_array_length(aad);
  int32_t ct_len = Moonbit_array_length(ciphertext);
  int32_t tag_len = Moonbit_array_length(tag);

  if (!EVP_DecryptInit_ex(ctx, EVP_aes_256_gcm(), NULL, NULL, NULL)) goto cleanup;
  if (!EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, nonce_len, NULL)) goto cleanup;
  if (!EVP_DecryptInit_ex(ctx, NULL, NULL, key, nonce)) goto cleanup;

  if (aad_len > 0) {
    if (!EVP_DecryptUpdate(ctx, NULL, &len, aad, aad_len)) goto cleanup;
  }

  if (!EVP_DecryptUpdate(ctx, plaintext_out, &len, ciphertext, ct_len)) goto cleanup;
  if (!EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_TAG, tag_len, tag)) goto cleanup;

  int ret = EVP_DecryptFinal_ex(ctx, plaintext_out + len, &len);
  if (ret > 0) {
    result = 0;
  }

cleanup:
  EVP_CIPHER_CTX_free(ctx);
  return result;
}

#endif

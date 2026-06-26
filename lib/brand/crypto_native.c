#include <moonbit.h>
#include <stdint.h>
#include <string.h>

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

// MoonBit fallback stubs for OpenSSL crypto.
//
// IMPORTANT (root-cause fix 2026-06-30):
//   These weak stubs were unconditionally compiled into libbrand.a and, because
//   GNU ld resolves a static archive's undefined symbols against object files
//   already on the link line BEFORE pulling new members from `-lcrypto`, the
//   weak (but *defined*) stubs here satisfied crypto_native.o's references to
//   RAND_bytes / EVP_* — so the real OpenSSL was never linked. The result was a
//   non-random nonce and AES-GCM that produced all-zero ciphertext / never
//   verified tags (every brand crypto test failed).
//
//   The stubs are now disabled by default. They are ONLY compiled when the build
//   explicitly opts out of OpenSSL via -DMBOPENCLACKY_NO_OPENSSL (e.g. a minimal
//   build on a platform with no libcrypto and no Windows CNG). In every normal
//   native build the real OpenSSL (Linux/macOS) or BCrypt (Windows) path in
//   crypto_native.c is used, with `-lcrypto` linked via moon.pkg link flags.
//
//   BUILD-TIME GUARD: the insecure stubs below are compiled ONLY when
//   MBOPENCLACKY_NO_OPENSSL is defined.  They must never reach a release or
//   production artifact.  Two independent guards enforce this:
//     (1) This file issues a hard #error unless MBOPENCLACKY_INSECURE_DEBUG_BUILD
//         is also defined, acknowledging a minimal/debug-only, no-real-crypto
//         build.  Without that acknowledgement the insecure stubs cannot be
//         compiled at all, so they cannot slip into a release artifact.
//     (2) CI runs scripts/check-crypto-build.{sh,ps1}, which fails any RELEASE
//         build performed with MBOPENCLACKY_NO_OPENSSL set.
#include <stdint.h>
#include <stdio.h>

#ifdef MBOPENCLACKY_NO_OPENSSL

/*
 * SECURITY WARNING (build-time):
 *   Compiling with MBOPENCLACKY_NO_OPENSSL disables real cryptographic
 *   primitives.  The stubs below provide *deterministic but insecure*
 *   placeholders.  NEVER ship a release build with this flag.
 */
#pragma message("WARNING: MBOPENCLACKY_NO_OPENSSL is defined — crypto stubs are INSECURE. Do not use in release builds!")

// (1) Hard compile-time guard.  Any build that opts out of real crypto MUST
//     explicitly acknowledge it is a minimal/debug-only build.  Without this
//     acknowledgement the insecure stubs cannot be compiled at all, which makes
//     it impossible for them to slip into a release artifact.
#ifndef MBOPENCLACKY_INSECURE_DEBUG_BUILD
#error "MBOPENCLACKY_NO_OPENSSL selected but MBOPENCLACKY_INSECURE_DEBUG_BUILD is not defined. " \
       "The insecure crypto stubs in brand_stubs.c are forbidden in every build that could ship. " \
       "Define MBOPENCLACKY_INSECURE_DEBUG_BUILD only for minimal/debug builds that explicitly opt out of real crypto, " \
       "or drop -DMBOPENCLACKY_NO_OPENSSL to use OpenSSL (Linux/macOS) / BCrypt (Windows)."
#endif

#ifdef _MSC_VER
#define MB_WEAK
#else
#define MB_WEAK __attribute__((weak))
#endif

// ── Random bytes (INSECURE placeholder — only for no-OpenSSL builds) ──
static int mbopenclacky_weak_stub_warned = 0;

MB_WEAK int32_t RAND_bytes(unsigned char* buf, int num) {
    if (!mbopenclacky_weak_stub_warned) {
        fprintf(stderr,
            "[MBOpenClacky] SECURITY WARNING: Using INSECURE crypto stubs "
            "(MBOPENCLACKY_NO_OPENSSL build). Do not use in production!\n");
        mbopenclacky_weak_stub_warned = 1;
    }
    for (int i = 0; i < num; i++) buf[i] = (unsigned char)(i % 256);
    return 1;
}

// ── EVP struct stub ───────────────────────────────────────────────────

typedef struct { int dummy; } EVP_CIPHER_CTX;
typedef struct { int dummy; } EVP_CIPHER;

static EVP_CIPHER evp_aes_256_gcm_val = {0};

MB_WEAK EVP_CIPHER_CTX* EVP_CIPHER_CTX_new(void) {
    static EVP_CIPHER_CTX ctx = {0};
    return &ctx;
}

MB_WEAK void EVP_CIPHER_CTX_free(EVP_CIPHER_CTX* ctx) { (void)ctx; }

MB_WEAK int32_t EVP_EncryptInit_ex(EVP_CIPHER_CTX* ctx, const EVP_CIPHER* type,
                           void* impl, const unsigned char* key,
                           const unsigned char* iv) {
    (void)ctx; (void)type; (void)impl; (void)key; (void)iv;
    return 1;
}

MB_WEAK int32_t EVP_DecryptInit_ex(EVP_CIPHER_CTX* ctx, const EVP_CIPHER* type,
                           void* impl, const unsigned char* key,
                           const unsigned char* iv) {
    (void)ctx; (void)type; (void)impl; (void)key; (void)iv;
    return 1;
}

MB_WEAK int32_t EVP_EncryptUpdate(EVP_CIPHER_CTX* ctx, unsigned char* out,
                          int* outl, const unsigned char* in, int inl) {
    (void)ctx; (void)out; (void)in;
    *outl = inl;
    return 1;
}

MB_WEAK int32_t EVP_DecryptUpdate(EVP_CIPHER_CTX* ctx, unsigned char* out,
                          int* outl, const unsigned char* in, int inl) {
    (void)ctx; (void)out; (void)in;
    *outl = inl;
    return 1;
}

MB_WEAK int32_t EVP_EncryptFinal_ex(EVP_CIPHER_CTX* ctx, unsigned char* out, int* outl) {
    (void)ctx; (void)out;
    *outl = 0;
    return 1;
}

MB_WEAK int32_t EVP_DecryptFinal_ex(EVP_CIPHER_CTX* ctx, unsigned char* out, int* outl) {
    (void)ctx; (void)out;
    *outl = 0;
    return 1;
}

MB_WEAK int32_t EVP_CIPHER_CTX_ctrl(EVP_CIPHER_CTX* ctx, int type, int arg, void* ptr) {
    (void)ctx; (void)type; (void)arg; (void)ptr;
    return 1;
}

MB_WEAK const EVP_CIPHER* EVP_aes_256_gcm(void) { return &evp_aes_256_gcm_val; }

#define EVP_CTRL_GCM_SET_IVLEN 0x9
#define EVP_CTRL_GCM_GET_TAG   0x10

#else  /* !MBOPENCLACKY_NO_OPENSSL */

// Real OpenSSL / BCrypt is used (see crypto_native.c). Provide a dummy
// translation unit symbol so the object file is non-empty and portable.
int mbopenclacky_brand_stubs_disabled = 1;

#endif /* MBOPENCLACKY_NO_OPENSSL */

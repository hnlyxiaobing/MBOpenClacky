// MoonBit stubs for OpenSSL crypto (weak — overridden by libcrypto in full builds)
#include <stdint.h>

#ifdef _MSC_VER
#define MB_WEAK
#else
#define MB_WEAK __attribute__((weak))
#endif

// ── Random bytes ──────────────────────────────────────────────────────

MB_WEAK int32_t RAND_bytes(unsigned char* buf, int num) {
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

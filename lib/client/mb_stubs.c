// MoonBit native stubs for system calls and curl
// curl stubs are weak symbols — overridden by opentui_stubs.c when both are linked
#include <stdlib.h>

// ── system() bridge ───────────────────────────────────────────────────

__attribute__((weak)) int32_t mb_system(const char* cmd) {
    return (int32_t)system(cmd);
}

// ── curl stubs (weak — overridden by opentui_stubs.c in full builds) ──

__attribute__((weak)) void* curl_easy_init(void) { return NULL; }
__attribute__((weak)) void curl_easy_cleanup(void* h) { (void)h; }
__attribute__((weak)) int curl_easy_setopt(void* h, int opt, ...) { (void)h; (void)opt; return 0; }
__attribute__((weak)) int curl_easy_perform(void* h) { (void)h; return 1; }
__attribute__((weak)) int curl_easy_getinfo(void* h, int info, void* p) { (void)h; (void)info; (void)p; return 1; }
__attribute__((weak)) const char* curl_easy_strerror(int code) { (void)code; return "curl stub"; }
__attribute__((weak)) struct curl_slist* curl_slist_append(struct curl_slist* list, const char* s) { (void)s; return list; }
__attribute__((weak)) void curl_slist_free_all(struct curl_slist* list) { (void)list; }

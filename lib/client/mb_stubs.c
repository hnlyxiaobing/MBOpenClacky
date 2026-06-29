// MoonBit native stubs for system calls and curl
// curl stubs are weak symbols — overridden by opentui_stubs.c when both are linked
#include <stdlib.h>
#include <stdint.h>

#ifdef _MSC_VER
#define MB_WEAK
#else
#define MB_WEAK __attribute__((weak))
#endif

// ── system() bridge ───────────────────────────────────────────────────
// On MSVC/Windows, mb_system and curl stubs are provided by opentui_stubs.c (onebit-tui)
// to avoid LNK2005 duplicate symbol errors (MSVC has no weak function definition support)
#ifndef _MSC_VER

MB_WEAK int32_t mb_system(const char* cmd) {
    return (int32_t)system(cmd);
}

// ── curl stubs (weak — overridden by opentui_stubs.c in full builds) ──

MB_WEAK void* curl_easy_init(void) { return NULL; }
MB_WEAK void curl_easy_cleanup(void* h) { (void)h; }
MB_WEAK int curl_easy_setopt(void* h, int opt, ...) { (void)h; (void)opt; return 0; }
MB_WEAK int curl_easy_perform(void* h) { (void)h; return 1; }
MB_WEAK int curl_easy_getinfo(void* h, int info, void* p) { (void)h; (void)info; (void)p; return 1; }
MB_WEAK const char* curl_easy_strerror(int code) { (void)code; return "curl stub"; }
MB_WEAK struct curl_slist* curl_slist_append(struct curl_slist* list, const char* s) { (void)s; return list; }
MB_WEAK void curl_slist_free_all(struct curl_slist* list) { (void)list; }

#endif // !_MSC_VER

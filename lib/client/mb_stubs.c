// MoonBit native stubs for system calls
// curl stubs removed — libcurl is linked directly via cc-link-flags
#include <stdlib.h>
#include <stdint.h>

#ifdef _MSC_VER
#define MB_WEAK
#else
#define MB_WEAK __attribute__((weak))
#endif

// ── system() bridge ───────────────────────────────────────────────────
// On MSVC/Windows, mb_system is provided by opentui_stubs.c (onebit-tui)
// to avoid LNK2005 duplicate symbol errors (MSVC has no weak function definition support)
#ifndef _MSC_VER

MB_WEAK int32_t mb_system(const char* cmd) {
    return (int32_t)system(cmd);
}

#endif // !_MSC_VER

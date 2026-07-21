// console_cp_native.c — Windows console code page management for MBOpenClacky TUI
// Windows: saves the current console input/output code pages and switches them to
// UTF-8 (CP 65001) so box-drawing / Braille / symbol glyphs render correctly.
// POSIX: no-op (terminals are already UTF-8 in practice).

#include <moonbit.h>

#ifdef _WIN32
  #define WIN32_LEAN_AND_MEAN
  #include <windows.h>
  #pragma comment(lib, "kernel32.lib")
#endif

// Saved original code pages, packed as (output_cp << 16) | input_cp.
// 0 means "nothing saved / already restored".
static int32_t g_saved_cp = 0;

/// Switch console output and input code pages to UTF-8 (65001).
/// Returns a token encoding the original code pages (pass it back to
/// mbopenclacky_restore_console_cp), or 0 if there is nothing to restore
/// (non-Windows, no console attached, or already switched).
MOONBIT_FFI_EXPORT
int32_t mbopenclacky_set_console_utf8(void) {
#ifdef _WIN32
  if (g_saved_cp != 0) return g_saved_cp; // already switched
  UINT out_cp = GetConsoleOutputCP();
  UINT in_cp = GetConsoleCP();
  // GetConsole*CP return 0 when there is no attached console (e.g. redirected).
  if (out_cp == 0 && in_cp == 0) return 0;
  if (out_cp != CP_UTF8) SetConsoleOutputCP(CP_UTF8);
  if (in_cp != CP_UTF8) SetConsoleCP(CP_UTF8);
  g_saved_cp = (int32_t)(((out_cp & 0xFFFF) << 16) | (in_cp & 0xFFFF));
  return g_saved_cp;
#else
  return 0;
#endif
}

/// Restore the console code pages saved by mbopenclacky_set_console_utf8.
/// Safe to call with 0 or any stale token (no-op in that case).
MOONBIT_FFI_EXPORT
void mbopenclacky_restore_console_cp(int32_t token) {
#ifdef _WIN32
  if (token == 0) return;
  UINT out_cp = (UINT)((token >> 16) & 0xFFFF);
  UINT in_cp = (UINT)(token & 0xFFFF);
  if (out_cp != 0) SetConsoleOutputCP(out_cp);
  if (in_cp != 0) SetConsoleCP(in_cp);
  if (g_saved_cp == token) g_saved_cp = 0;
#else
  (void)token;
#endif
}

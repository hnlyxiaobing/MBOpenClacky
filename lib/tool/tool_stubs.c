// C stubs for lib/tool native functions

// mb_system: execute a shell command via C standard library system().
// Previously provided by onebit-tui/ffi's opentui_stubs.c; now implemented
// locally since we removed the onebit-tui dependency.
#include <stdlib.h>

int mb_system(const char *cmd) {
  return system(cmd);
}

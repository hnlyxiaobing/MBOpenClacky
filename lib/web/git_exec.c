#include <stdlib.h>
#include <string.h>

int git_system(const char *cmd) {
    return system(cmd);
}

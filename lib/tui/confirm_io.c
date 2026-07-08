// confirm_io.c — Synchronous I/O for confirmation prompts
//
// These functions bypass the async I/O system to read/write
// directly from file descriptors. Used by the confirmation
// callback which must be synchronous (called from agent.run()).

#include <unistd.h>
#include <poll.h>
#include <string.h>

// Read a single byte from the given file descriptor.
// Returns the byte value (0-255) or -1 on timeout/error.
// timeout_ms = -1 for infinite wait.
int sync_read_byte_fd(int fd, int timeout_ms) {
    struct pollfd pfd;
    pfd.fd = fd;
    pfd.events = POLLIN;
    pfd.revents = 0;
    int ret = poll(&pfd, 1, timeout_ms);
    if (ret > 0 && (pfd.revents & POLLIN)) {
        unsigned char buf[1];
        ssize_t n = read(fd, buf, 1);
        if (n == 1) {
            return (int)buf[0];
        }
    }
    return -1;
}

// Write a string to the given file descriptor.
void sync_write_fd(int fd, const char* data, int len) {
    if (len <= 0) return;
    // Write may not send all bytes in one call, so loop
    int remaining = len;
    const char* ptr = data;
    while (remaining > 0) {
        ssize_t n = write(fd, ptr, remaining);
        if (n <= 0) break;
        ptr += n;
        remaining -= n;
    }
}

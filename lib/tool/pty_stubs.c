/*
 * pty_stubs.c — POSIX pseudo-terminal FFI stubs for MBOpenClacky
 *
 * Provides forkpty-based PTY creation, non-blocking read with timeout,
 * write, close, wait, kill, resize, and monotonic time.
 *
 * On Windows (Phase 2), all functions return -1 or error to indicate
 * PTY is unavailable; the MoonBit layer falls back to system().
 */

#ifndef _WIN32

/* ---- POSIX implementation ---- */

#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/select.h>
#include <sys/ioctl.h>
#include <signal.h>
#include <termios.h>
#include <time.h>

#ifdef __linux__
  #include <pty.h>      /* forkpty, openpty */
#elif defined(__APPLE__)
  #include <util.h>     /* forkpty on macOS */
#else
  /* BSD, others — try pty.h */
  #include <pty.h>
#endif

/* MB_EXPORT visible to MoonBit FFI */
#define MB_EXPORT __attribute__((visibility("default")))

/*
 * mb_pty_spawn — create a child process in a new pseudo-terminal.
 *
 * Parameters:
 *   shell  — path to shell binary (e.g. "/bin/bash")
 *   cwd    — working directory for child (or NULL)
 *   cols   — initial terminal width (e.g. 80)
 *   rows   — initial terminal height (e.g. 24)
 *   out_pid — receives child PID (caller-allocated int)
 *
 * Returns: master fd (>= 0) on success, -1 on failure.
 * The caller owns the fd and must close it after waitpid.
 */
MB_EXPORT int mb_pty_spawn(const char *shell, const char *cwd,
                           int cols, int rows, int *out_pid)
{
    if (!shell || !out_pid) {
        return -1;
    }

    int master_fd = -1;
    pid_t pid = -1;

    /* struct winsize for terminal dimensions */
    struct winsize ws;
    ws.ws_col = cols > 0 ? cols : 80;
    ws.ws_row = rows > 0 ? rows : 24;
    ws.ws_xpixel = 0;
    ws.ws_ypixel = 0;

    pid = forkpty(&master_fd, NULL, NULL, &ws);
    if (pid < 0) {
        return -1;
    }

    if (pid == 0) {
        /* ---- Child process ---- */
        /* Change working directory if specified */
        if (cwd && *cwd) {
            chdir(cwd);
        }

        /* Set environment variables for clean PTY session */
        setenv("TERM", "dumb", 1);          /* dumb terminal — no escape sequences */
        setenv("PS1", "", 1);                /* empty prompt */
        setenv("HISTFILE", "/dev/null", 1);  /* disable history */
        setenv("HISTSIZE", "0", 1);          /* no history */
        unsetenv("PROMPT_COMMAND");           /* disable pre-prompt hooks */

        /* exec shell with -i (interactive) flag for job control support */
        char *args[] = { (char *)shell, "-i", NULL };
        execvp(shell, args);

        /* If exec fails, exit immediately */
        _exit(127);
    }

    /* ---- Parent process ---- */
    *out_pid = (int)pid;
    return master_fd;
}

/*
 * mb_pty_read — read from PTY master fd with timeout.
 *
 * Parameters:
 *   fd         — master PTY file descriptor
 *   buf        — caller-allocated buffer (at least max_bytes)
 *   max_bytes  — buffer capacity
 *   timeout_ms — timeout in milliseconds (< 0 = blocking)
 *
 * Returns:
 *   > 0  — number of bytes read
 *   0    — timeout, no data available
 *   -1   — EOF or error (child exited)
 */
MB_EXPORT int mb_pty_read(int fd, char *buf, int max_bytes, int timeout_ms)
{
    if (!buf || max_bytes <= 0) {
        return -1;
    }

    fd_set rfds;
    FD_ZERO(&rfds);
    FD_SET(fd, &rfds);

    struct timeval tv;
    if (timeout_ms >= 0) {
        tv.tv_sec  = timeout_ms / 1000;
        tv.tv_usec = (timeout_ms % 1000) * 1000;
    }

    int ret = select(fd + 1, &rfds, NULL, NULL, timeout_ms >= 0 ? &tv : NULL);
    if (ret < 0) {
        if (errno == EINTR) {
            return 0;  /* interrupted by signal — treat as timeout */
        }
        return -1;     /* real error */
    }
    if (ret == 0) {
        return 0;       /* timeout */
    }

    /* Data is available */
    ssize_t n = read(fd, buf, max_bytes);
    if (n <= 0) {
        /* EOF (n==0) or error — child likely exited.
         * On Linux, reading a PTY after child exit gives EIO. */
        return -1;
    }
    return (int)n;
}

/*
 * mb_pty_write — write data to PTY master fd.
 *
 * Parameters:
 *   fd   — master PTY file descriptor
 *   data — bytes to write
 *   len  — number of bytes
 *
 * Returns: number of bytes written, or -1 on error.
 */
MB_EXPORT int mb_pty_write(int fd, const char *data, int len)
{
    if (!data || len <= 0) {
        return 0;
    }
    int total = 0;
    while (total < len) {
        ssize_t n = write(fd, data + total, len - total);
        if (n < 0) {
            if (errno == EINTR) {
                continue;  /* retry on signal */
            }
            return -1;     /* real error */
        }
        if (n == 0) {
            break;  /* shouldn't happen for PTY */
        }
        total += (int)n;
    }
    return total;
}

/*
 * mb_pty_close_fd — close the master PTY fd.
 */
MB_EXPORT void mb_pty_close_fd(int fd)
{
    if (fd >= 0) {
        close(fd);
    }
}

/*
 * mb_pty_wait — wait for child process.
 *
 * Parameters:
 *   pid    — child PID
 *   nohang — if non-zero, WNOHANG (return immediately if not exited)
 *
 * Returns:
 *   >= 0    — exit status (use WEXITSTATUS / WTERMSIG to decode)
 *   -1      — error (e.g. child already reaped)
 *   -2      — nohang and child still running (via WNOHANG returning 0)
 */
MB_EXPORT int mb_pty_wait(int pid, int nohang)
{
    int status = 0;
    int options = nohang ? WNOHANG : 0;
    pid_t r = waitpid(pid, &status, options);
    if (r < 0) {
        return -1;
    }
    if (r == 0) {
        /* WNOHANG and child hasn't exited yet */
        return -2;
    }
    return status;
}

/*
 * mb_pty_kill_pid — send SIGTERM to child, then SIGKILL after 2s if still alive.
 *
 * Returns: 0 on success (process killed or already dead), -1 on error.
 */
MB_EXPORT int mb_pty_kill_pid(int pid)
{
    if (pid <= 0) {
        return -1;
    }
    /* Send SIGTERM first for graceful shutdown */
    if (kill(pid, SIGTERM) < 0) {
        if (errno == ESRCH) {
            return 0;  /* already dead */
        }
    }
    /* Wait briefly (1 second) */
    usleep(1000000);  /* 1 second */

    /* Check if still alive; if so, SIGKILL */
    int status;
    pid_t r = waitpid(pid, &status, WNOHANG);
    if (r == 0) {
        /* Still running — force kill */
        kill(pid, SIGKILL);
        waitpid(pid, &status, 0);  /* reap zombie */
    }
    return 0;
}

/*
 * mb_pty_resize — resize the PTY window.
 *
 * Returns: 0 on success, -1 on error.
 */
MB_EXPORT int mb_pty_resize(int fd, int cols, int rows)
{
    struct winsize ws;
    ws.ws_col = cols;
    ws.ws_row = rows;
    ws.ws_xpixel = 0;
    ws.ws_ypixel = 0;
    return ioctl(fd, TIOCSWINSZ, &ws);
}

/*
 * mb_pty_available — check if PTY is supported on this platform.
 *
 * Returns: 1 on POSIX (always available), 0 on Windows.
 */
MB_EXPORT int mb_pty_available(void)
{
    return 1;
}

/*
 * mb_pty_time_ms — monotonic time in milliseconds.
 *
 * Uses CLOCK_MONOTONIC for reliable elapsed-time measurement.
 * Returns: milliseconds since some unspecified starting point.
 */
MB_EXPORT int mb_pty_time_ms(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int)(ts.tv_sec * 1000 + ts.tv_nsec / 1000000);
}

#else /* _WIN32 */

/* ---- Windows stubs (Phase 2: ConPTY or pipe simulation) ---- */

#define MB_EXPORT __declspec(dllexport)

MB_EXPORT int mb_pty_spawn(const char *shell, const char *cwd,
                           int cols, int rows, int *out_pid)
{
    (void)shell; (void)cwd; (void)cols; (void)rows; (void)out_pid;
    return -1;  /* PTY not available on Windows yet */
}

MB_EXPORT int mb_pty_read(int fd, char *buf, int max_bytes, int timeout_ms)
{
    (void)fd; (void)buf; (void)max_bytes; (void)timeout_ms;
    return -1;
}

MB_EXPORT int mb_pty_write(int fd, const char *data, int len)
{
    (void)fd; (void)data; (void)len;
    return -1;
}

MB_EXPORT void mb_pty_close_fd(int fd)
{
    (void)fd;
}

MB_EXPORT int mb_pty_wait(int pid, int nohang)
{
    (void)pid; (void)nohang;
    return -1;
}

MB_EXPORT int mb_pty_kill_pid(int pid)
{
    (void)pid;
    return -1;
}

MB_EXPORT int mb_pty_resize(int fd, int cols, int rows)
{
    (void)fd; (void)cols; (void)rows;
    return -1;
}

MB_EXPORT int mb_pty_available(void)
{
    return 0;  /* not available on Windows */
}

MB_EXPORT int mb_pty_time_ms(void)
{
    return 0;
}

#endif /* _WIN32 */

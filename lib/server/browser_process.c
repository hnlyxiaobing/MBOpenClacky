/*
 * Browser process management FFI for MBOpenClacky.
 * Provides child process spawning with stdin/stdout pipes for JSON-RPC communication.
 */

#include <moonbit.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>

#ifdef _WIN32

#include <windows.h>

#define MAX_HANDLES 16
#define READ_BUF_SIZE 65536

typedef struct {
  int valid;
  DWORD pid;
  HANDLE hProcess;
  HANDLE stdin_write;
  HANDLE stdout_read;
  char *line_buf;
  int line_buf_len;
  int line_buf_cap;
} browser_proc_t;

static browser_proc_t g_procs[MAX_HANDLES];
static int g_procs_init = 0;

static void ensure_init() {
  if (!g_procs_init) {
    memset(g_procs, 0, sizeof(g_procs));
    g_procs_init = 1;
  }
}

static int alloc_handle() {
  ensure_init();
  for (int i = 0; i < MAX_HANDLES; i++) {
    if (!g_procs[i].valid) return i;
  }
  return -1;
}

/* Convert MoonBit UTF-16 string to UTF-8 C string. Caller must free. */
static char *mbstr_to_utf8(moonbit_string_t str) {
  struct moonbit_object *hdr = (struct moonbit_object *)((char *)str - 8);
  int len = hdr->arr.len; /* number of uint16_t code units */
  int cap = len * 3 + 1;
  char *buf = (char *)malloc(cap);
  if (!buf) return NULL;
  int j = 0;
  for (int i = 0; i < len; i++) {
    uint16_t c = str[i];
    if (c < 0x80) {
      buf[j++] = (char)c;
    } else if (c < 0x800) {
      buf[j++] = (char)(0xC0 | (c >> 6));
      buf[j++] = (char)(0x80 | (c & 0x3F));
    } else {
      buf[j++] = (char)(0xE0 | (c >> 12));
      buf[j++] = (char)(0x80 | ((c >> 6) & 0x3F));
      buf[j++] = (char)(0x80 | (c & 0x3F));
    }
  }
  buf[j] = '\0';
  return buf;
}

/* Get element from a MoonBit ref array (Array[String]) */
static moonbit_string_t ref_array_get(moonbit_ref_array_t arr, int index) {
  struct moonbit_object *hdr = (struct moonbit_object *)((char *)arr - 8);
  (void)hdr;
  return arr[index];
}

static int ref_array_length(moonbit_ref_array_t arr) {
  struct moonbit_object *hdr = (struct moonbit_object *)((char *)arr - 8);
  return hdr->arr.len;
}

static int bytes_length(moonbit_bytes_t buf) {
  struct moonbit_object *hdr = (struct moonbit_object *)((char *)buf - 8);
  return hdr->arr.len;
}

/* Append bytes to a handle's line buffer */
static void append_to_buf(int handle, const char *data, int len) {
  browser_proc_t *p = &g_procs[handle];
  while (p->line_buf_len + len > p->line_buf_cap) {
    int new_cap = p->line_buf_cap == 0 ? 4096 : p->line_buf_cap * 2;
    char *new_buf = (char *)realloc(p->line_buf, new_cap);
    if (!new_buf) return;
    p->line_buf = new_buf;
    p->line_buf_cap = new_cap;
  }
  memcpy(p->line_buf + p->line_buf_len, data, len);
  p->line_buf_len += len;
}

MOONBIT_FFI_EXPORT
int32_t mbopenclacky_spawn_process(
  moonbit_string_t command,
  moonbit_ref_array_t args,
  int32_t arg_count
) {
  /* Defensive check: clamp arg_count to actual array length */
  int actual_len = ref_array_length(args);
  if (arg_count > actual_len) arg_count = actual_len;

  int handle = alloc_handle();
  if (handle < 0) return -1;

  char *cmd_utf8 = mbstr_to_utf8(command);
  if (!cmd_utf8) return -1;

  /* Build command line: "cmd" "arg1" "arg2" ... */
  int cmd_len = (int)strlen(cmd_utf8);
  int total_len = cmd_len + 2; /* quotes + null */
  for (int i = 0; i < arg_count; i++) {
    char *arg = mbstr_to_utf8(ref_array_get(args, i));
    if (arg) {
      total_len += (int)strlen(arg) + 3; /* space + quotes + null */
      free(arg);
    }
  }

  char *cmdline = (char *)malloc(total_len + 1);
  if (!cmdline) { free(cmd_utf8); return -1; }

  int pos = 0;
  cmdline[pos++] = '"';
  memcpy(cmdline + pos, cmd_utf8, cmd_len);
  pos += cmd_len;
  cmdline[pos++] = '"';

  for (int i = 0; i < arg_count; i++) {
    cmdline[pos++] = ' ';
    char *arg = mbstr_to_utf8(ref_array_get(args, i));
    if (arg) {
      cmdline[pos++] = '"';
      int alen = (int)strlen(arg);
      memcpy(cmdline + pos, arg, alen);
      pos += alen;
      cmdline[pos++] = '"';
      free(arg);
    }
  }
  cmdline[pos] = '\0';
  free(cmd_utf8);

  /* Create pipes */
  SECURITY_ATTRIBUTES sa;
  sa.nLength = sizeof(SECURITY_ATTRIBUTES);
  sa.bInheritHandle = TRUE;
  sa.lpSecurityDescriptor = NULL;

  HANDLE stdin_r, stdin_w, stdout_r, stdout_w;
  if (!CreatePipe(&stdin_r, &stdin_w, &sa, 0) ||
      !CreatePipe(&stdout_r, &stdout_w, &sa, 0)) {
    free(cmdline);
    return -1;
  }

  SetHandleInformation(stdin_w, HANDLE_FLAG_INHERIT, 0);
  SetHandleInformation(stdout_r, HANDLE_FLAG_INHERIT, 0);

  STARTUPINFOA si;
  PROCESS_INFORMATION pi;
  ZeroMemory(&si, sizeof(si));
  si.cb = sizeof(si);
  si.dwFlags = STARTF_USESTDHANDLES;
  si.hStdInput = stdin_r;
  si.hStdOutput = stdout_w;
  si.hStdError = GetStdHandle(STD_ERROR_HANDLE);
  ZeroMemory(&pi, sizeof(pi));

  BOOL ok = CreateProcessA(NULL, cmdline, NULL, NULL, TRUE,
                           CREATE_NO_WINDOW, NULL, NULL, &si, &pi);
  free(cmdline);
  CloseHandle(stdin_r);
  CloseHandle(stdout_w);

  if (!ok) {
    CloseHandle(stdin_w);
    CloseHandle(stdout_r);
    return -1;
  }

  CloseHandle(pi.hThread);
  g_procs[handle].valid = 1;
  g_procs[handle].pid = pi.dwProcessId;
  g_procs[handle].hProcess = pi.hProcess;
  g_procs[handle].stdin_write = stdin_w;
  g_procs[handle].stdout_read = stdout_r;
  g_procs[handle].line_buf = NULL;
  g_procs[handle].line_buf_len = 0;
  g_procs[handle].line_buf_cap = 0;

  return handle;
}

MOONBIT_FFI_EXPORT
int32_t mbopenclacky_is_process_alive(int32_t handle) {
  if (handle < 0 || handle >= MAX_HANDLES || !g_procs[handle].valid)
    return 0;
  DWORD exit_code;
  if (GetExitCodeProcess(g_procs[handle].hProcess, &exit_code)) {
    return exit_code == STILL_ACTIVE ? 1 : 0;
  }
  return 0;
}

MOONBIT_FFI_EXPORT
int32_t mbopenclacky_terminate_process(int32_t handle) {
  if (handle < 0 || handle >= MAX_HANDLES || !g_procs[handle].valid)
    return -1;
  TerminateProcess(g_procs[handle].hProcess, 1);
  return 0;
}

MOONBIT_FFI_EXPORT
int32_t mbopenclacky_write_process_stdin(
  int32_t handle,
  moonbit_bytes_t data,
  int32_t length
) {
  if (handle < 0 || handle >= MAX_HANDLES || !g_procs[handle].valid)
    return -1;
  DWORD written;
  if (!WriteFile(g_procs[handle].stdin_write, data, (DWORD)length, &written, NULL))
    return -1;
  FlushFileBuffers(g_procs[handle].stdin_write);
  return 0;
}

MOONBIT_FFI_EXPORT
int32_t mbopenclacky_read_process_stdout_line(
  int32_t handle,
  moonbit_bytes_t buffer,
  int32_t buffer_size
) {
  if (handle < 0 || handle >= MAX_HANDLES || !g_procs[handle].valid)
    return -1;

  browser_proc_t *p = &g_procs[handle];
  HANDLE h = p->stdout_read;

  /* Check if we already have a complete line in the buffer */
  for (int i = 0; i < p->line_buf_len; i++) {
    if (p->line_buf[i] == '\n') {
      int line_len = i;
      if (line_len > 0 && p->line_buf[line_len - 1] == '\r')
        line_len--;
      if (line_len > buffer_size) line_len = buffer_size;
      memcpy(buffer, p->line_buf, line_len);
      /* Remove the consumed line from buffer */
      int remaining = p->line_buf_len - (i + 1);
      if (remaining > 0)
        memmove(p->line_buf, p->line_buf + i + 1, remaining);
      p->line_buf_len = remaining;
      return line_len;
    }
  }

  /* Read more data from pipe (with 30s timeout) */
  char tmp[4096];
  DWORD avail = 0;
  int timeout_count = 0;
  while (1) {
    if (!PeekNamedPipe(h, NULL, 0, NULL, &avail, NULL)) {
      /* Pipe broken */
      return -1;
    }
    if (avail > 0) {
      DWORD to_read = avail < sizeof(tmp) ? avail : sizeof(tmp);
      DWORD actual;
      if (!ReadFile(h, tmp, to_read, &actual, NULL) || actual == 0)
        return -1;
      append_to_buf(handle, tmp, (int)actual);

      /* Check for newline in newly read data */
      for (int i = p->line_buf_len - (int)actual; i < p->line_buf_len; i++) {
        if (p->line_buf[i] == '\n') {
          int line_len = i;
          if (line_len > 0 && p->line_buf[line_len - 1] == '\r')
            line_len--;
          if (line_len > buffer_size) line_len = buffer_size;
          memcpy(buffer, p->line_buf, line_len);
          int remaining = p->line_buf_len - (i + 1);
          if (remaining > 0)
            memmove(p->line_buf, p->line_buf + i + 1, remaining);
          p->line_buf_len = remaining;
          return line_len;
        }
      }
    } else {
      /* No data available, sleep briefly and retry with timeout */
      Sleep(10);
      timeout_count++;
      if (timeout_count >= 3000) {
        /* 30s timeout (3000 x 10ms) */
        if (p->line_buf_len > 0) {
          int line_len = p->line_buf_len;
          if (line_len > buffer_size) line_len = buffer_size;
          memcpy(buffer, p->line_buf, line_len);
          p->line_buf_len = 0;
          return line_len;
        }
        return -2; /* timeout */
      }
      /* Check if process is still alive */
      DWORD exit_code;
      if (GetExitCodeProcess(p->hProcess, &exit_code) && exit_code != STILL_ACTIVE) {
        /* Process exited, return any remaining data */
        if (p->line_buf_len > 0) {
          int line_len = p->line_buf_len;
          if (line_len > buffer_size) line_len = buffer_size;
          memcpy(buffer, p->line_buf, line_len);
          p->line_buf_len = 0;
          return line_len;
        }
        return -1;
      }
    }
  }
}

MOONBIT_FFI_EXPORT
int32_t mbopenclacky_get_process_pid(int32_t handle) {
  if (handle < 0 || handle >= MAX_HANDLES || !g_procs[handle].valid)
    return -1;
  return (int32_t)g_procs[handle].pid;
}

MOONBIT_FFI_EXPORT
int32_t mbopenclacky_close_process_handle(int32_t handle) {
  if (handle < 0 || handle >= MAX_HANDLES || !g_procs[handle].valid)
    return -1;
  browser_proc_t *p = &g_procs[handle];
  if (p->hProcess) CloseHandle(p->hProcess);
  if (p->stdin_write) CloseHandle(p->stdin_write);
  if (p->stdout_read) CloseHandle(p->stdout_read);
  if (p->line_buf) free(p->line_buf);
  memset(p, 0, sizeof(browser_proc_t));
  return 0;
}

#else /* POSIX (Linux/macOS) */

#include <unistd.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <signal.h>
#include <errno.h>
#include <fcntl.h>

#define MAX_HANDLES 16
#define READ_BUF_SIZE 65536

typedef struct {
  int valid;
  pid_t pid;
  int stdin_fd;
  int stdout_fd;
  char *line_buf;
  int line_buf_len;
  int line_buf_cap;
} browser_proc_posix_t;

static browser_proc_posix_t g_procs[MAX_HANDLES];
static int g_procs_init = 0;

static void ensure_init() {
  if (!g_procs_init) {
    memset(g_procs, 0, sizeof(g_procs));
    g_procs_init = 1;
  }
}

static int alloc_handle() {
  ensure_init();
  for (int i = 0; i < MAX_HANDLES; i++) {
    if (!g_procs[i].valid) return i;
  }
  return -1;
}

static char *mbstr_to_utf8(moonbit_string_t str) {
  struct moonbit_object *hdr = (struct moonbit_object *)((char *)str - 8);
  int len = hdr->arr.len;
  int cap = len * 3 + 1;
  char *buf = (char *)malloc(cap);
  if (!buf) return NULL;
  int j = 0;
  for (int i = 0; i < len; i++) {
    uint16_t c = str[i];
    if (c < 0x80) {
      buf[j++] = (char)c;
    } else if (c < 0x800) {
      buf[j++] = (char)(0xC0 | (c >> 6));
      buf[j++] = (char)(0x80 | (c & 0x3F));
    } else {
      buf[j++] = (char)(0xE0 | (c >> 12));
      buf[j++] = (char)(0x80 | ((c >> 6) & 0x3F));
      buf[j++] = (char)(0x80 | (c & 0x3F));
    }
  }
  buf[j] = '\0';
  return buf;
}

static moonbit_string_t ref_array_get(moonbit_ref_array_t arr, int index) {
  return arr[index];
}

static int ref_array_length(moonbit_ref_array_t arr) {
  struct moonbit_object *hdr = (struct moonbit_object *)((char *)arr - 8);
  return hdr->arr.len;
}

static int bytes_length(moonbit_bytes_t buf) {
  struct moonbit_object *hdr = (struct moonbit_object *)((char *)buf - 8);
  return hdr->arr.len;
}

static void append_to_buf(int handle, const char *data, int len) {
  browser_proc_posix_t *p = &g_procs[handle];
  while (p->line_buf_len + len > p->line_buf_cap) {
    int new_cap = p->line_buf_cap == 0 ? 4096 : p->line_buf_cap * 2;
    char *new_buf = (char *)realloc(p->line_buf, new_cap);
    if (!new_buf) return;
    p->line_buf = new_buf;
    p->line_buf_cap = new_cap;
  }
  memcpy(p->line_buf + p->line_buf_len, data, len);
  p->line_buf_len += len;
}

MOONBIT_FFI_EXPORT
int32_t mbopenclacky_spawn_process(
  moonbit_string_t command,
  moonbit_ref_array_t args,
  int32_t arg_count
) {
  int handle = alloc_handle();
  if (handle < 0) return -1;

  /* Defensive check: clamp arg_count to actual array length */
  int actual_len = ref_array_length(args);
  if (arg_count > actual_len) arg_count = actual_len;

  char *cmd_utf8 = mbstr_to_utf8(command);
  if (!cmd_utf8) return -1;

  /* Build argv array */
  char **argv = (char **)malloc(sizeof(char *) * (arg_count + 2));
  if (!argv) { free(cmd_utf8); return -1; }
  argv[0] = cmd_utf8;
  for (int i = 0; i < arg_count; i++) {
    argv[i + 1] = mbstr_to_utf8(ref_array_get(args, i));
  }
  argv[arg_count + 1] = NULL;

  int stdin_pipe[2], stdout_pipe[2];
  if (pipe(stdin_pipe) < 0 || pipe(stdout_pipe) < 0) {
    for (int i = 0; i <= arg_count; i++) free(argv[i]);
    free(argv);
    return -1;
  }

  pid_t pid = fork();
  if (pid < 0) {
    close(stdin_pipe[0]); close(stdin_pipe[1]);
    close(stdout_pipe[0]); close(stdout_pipe[1]);
    for (int i = 0; i <= arg_count; i++) free(argv[i]);
    free(argv);
    return -1;
  }

  if (pid == 0) {
    /* Child */
    close(stdin_pipe[1]);
    close(stdout_pipe[0]);
    dup2(stdin_pipe[0], STDIN_FILENO);
    dup2(stdout_pipe[1], STDOUT_FILENO);
    close(stdin_pipe[0]);
    close(stdout_pipe[1]);
    execvp(cmd_utf8, argv);
    _exit(127);
  }

  /* Parent */
  close(stdin_pipe[0]);
  close(stdout_pipe[1]);
  for (int i = 0; i <= arg_count; i++) free(argv[i]);
  free(argv);

  /* Set stdout pipe to non-blocking for read */
  int flags = fcntl(stdout_pipe[0], F_GETFL, 0);
  fcntl(stdout_pipe[0], F_SETFL, flags | O_NONBLOCK);

  g_procs[handle].valid = 1;
  g_procs[handle].pid = pid;
  g_procs[handle].stdin_fd = stdin_pipe[1];
  g_procs[handle].stdout_fd = stdout_pipe[0];
  g_procs[handle].line_buf = NULL;
  g_procs[handle].line_buf_len = 0;
  g_procs[handle].line_buf_cap = 0;

  return handle;
}

MOONBIT_FFI_EXPORT
int32_t mbopenclacky_is_process_alive(int32_t handle) {
  if (handle < 0 || handle >= MAX_HANDLES || !g_procs[handle].valid)
    return 0;
  /* Use kill(pid, 0) to check existence without reaping the zombie */
  return (kill(g_procs[handle].pid, 0) == 0) ? 1 : 0;
}

MOONBIT_FFI_EXPORT
int32_t mbopenclacky_terminate_process(int32_t handle) {
  if (handle < 0 || handle >= MAX_HANDLES || !g_procs[handle].valid)
    return -1;
  kill(g_procs[handle].pid, SIGTERM);
  usleep(100000); /* 100ms grace period */
  kill(g_procs[handle].pid, SIGKILL);
  return 0;
}

MOONBIT_FFI_EXPORT
int32_t mbopenclacky_write_process_stdin(
  int32_t handle,
  moonbit_bytes_t data,
  int32_t length
) {
  if (handle < 0 || handle >= MAX_HANDLES || !g_procs[handle].valid)
    return -1;
  ssize_t written = write(g_procs[handle].stdin_fd, data, length);
  return (written == length) ? 0 : -1;
}

MOONBIT_FFI_EXPORT
int32_t mbopenclacky_read_process_stdout_line(
  int32_t handle,
  moonbit_bytes_t buffer,
  int32_t buffer_size
) {
  if (handle < 0 || handle >= MAX_HANDLES || !g_procs[handle].valid)
    return -1;

  browser_proc_posix_t *p = &g_procs[handle];

  /* Check buffered data for newline */
  for (int i = 0; i < p->line_buf_len; i++) {
    if (p->line_buf[i] == '\n') {
      int line_len = i;
      if (line_len > 0 && p->line_buf[line_len - 1] == '\r')
        line_len--;
      if (line_len > buffer_size) line_len = buffer_size;
      memcpy(buffer, p->line_buf, line_len);
      int remaining = p->line_buf_len - (i + 1);
      if (remaining > 0)
        memmove(p->line_buf, p->line_buf + i + 1, remaining);
      p->line_buf_len = remaining;
      return line_len;
    }
  }

  /* Read more from pipe (with 30s timeout) */
  char tmp[4096];
  int timeout_count = 0;
  while (1) {
    ssize_t n = read(p->stdout_fd, tmp, sizeof(tmp));
    if (n > 0) {
      append_to_buf(handle, tmp, (int)n);
      /* Check for newline in newly read data */
      for (int i = p->line_buf_len - (int)n; i < p->line_buf_len; i++) {
        if (p->line_buf[i] == '\n') {
          int line_len = i;
          if (line_len > 0 && p->line_buf[line_len - 1] == '\r')
            line_len--;
          if (line_len > buffer_size) line_len = buffer_size;
          memcpy(buffer, p->line_buf, line_len);
          int remaining = p->line_buf_len - (i + 1);
          if (remaining > 0)
            memmove(p->line_buf, p->line_buf + i + 1, remaining);
          p->line_buf_len = remaining;
          return line_len;
        }
      }
    } else if (n == 0) {
      /* EOF - return any remaining data */
      if (p->line_buf_len > 0) {
        int line_len = p->line_buf_len;
        if (line_len > buffer_size) line_len = buffer_size;
        memcpy(buffer, p->line_buf, line_len);
        p->line_buf_len = 0;
        return line_len;
      }
      return -1;
    } else {
      /* EAGAIN/EWOULDBLOCK - no data available yet */
      if (errno == EAGAIN || errno == EWOULDBLOCK) {
        usleep(10000); /* 10ms */
        timeout_count++;
        if (timeout_count >= 3000) {
          /* 30s timeout (3000 x 10ms) */
          if (p->line_buf_len > 0) {
            int line_len = p->line_buf_len;
            if (line_len > buffer_size) line_len = buffer_size;
            memcpy(buffer, p->line_buf, line_len);
            p->line_buf_len = 0;
            return line_len;
          }
          return -2; /* timeout */
        }
        /* Check if process is alive (without reaping) */
        if (kill(p->pid, 0) != 0) {
          if (p->line_buf_len > 0) {
            int line_len = p->line_buf_len;
            if (line_len > buffer_size) line_len = buffer_size;
            memcpy(buffer, p->line_buf, line_len);
            p->line_buf_len = 0;
            return line_len;
          }
          return -1;
        }
        continue;
      }
      return -1;
    }
  }
}

MOONBIT_FFI_EXPORT
int32_t mbopenclacky_get_process_pid(int32_t handle) {
  if (handle < 0 || handle >= MAX_HANDLES || !g_procs[handle].valid)
    return -1;
  return (int32_t)g_procs[handle].pid;
}

MOONBIT_FFI_EXPORT
int32_t mbopenclacky_close_process_handle(int32_t handle) {
  if (handle < 0 || handle >= MAX_HANDLES || !g_procs[handle].valid)
    return -1;
  browser_proc_posix_t *p = &g_procs[handle];
  /* Reap zombie process if it has exited */
  waitpid(p->pid, NULL, WNOHANG);
  if (p->stdin_fd >= 0) close(p->stdin_fd);
  if (p->stdout_fd >= 0) close(p->stdout_fd);
  if (p->line_buf) free(p->line_buf);
  memset(p, 0, sizeof(browser_proc_posix_t));
  return 0;
}

#endif

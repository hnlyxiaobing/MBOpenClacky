// C wrapper for OpenTUI Zig library
// This wrapper provides a simpler interface for MoonBit FFI and adapts
// across evolving Zig exports by probing symbols at runtime when needed.

#define _GNU_SOURCE
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <stddef.h>
#include <stdio.h>
#if defined(__APPLE__) || defined(__linux__)
#include <dlfcn.h>
#elif defined(_WIN32)
#include <windows.h>
#endif

// Forward declarations for opaque types
typedef void* RendererPtr;
typedef void* BufferPtr;

// External Zig functions from libopentui.* (newer signature with testing parameter)
extern RendererPtr createRenderer(uint32_t width, uint32_t height, bool testing);

// Wrapper for createRenderer
RendererPtr createRendererDebug(uint32_t width, uint32_t height) {
    // Pass false for testing parameter since we're running for real
    return createRenderer(width, height, false);
}
extern void destroyRenderer(RendererPtr renderer, bool useAlternateScreen, uint32_t splitHeight);
extern void setUseThread(RendererPtr renderer, bool useThread);
extern void setBackgroundColor(RendererPtr renderer, const float* color);
extern void render(RendererPtr renderer, bool force);
extern BufferPtr getNextBuffer(RendererPtr renderer);
extern BufferPtr getCurrentBuffer(RendererPtr renderer);

// The newer Zig API for createOptimizedBuffer takes more parameters
extern BufferPtr createOptimizedBuffer(uint32_t width, uint32_t height, bool respectAlpha, uint8_t widthMethod, const uint8_t* idPtr, size_t idLen);

// Wrapper for older API that MoonBit expects
BufferPtr createOptimizedBufferSimple(uint32_t width, uint32_t height, bool respectAlpha) {
    const char* empty_id = "";
    return createOptimizedBuffer(width, height, respectAlpha, 0, (const uint8_t*)empty_id, 0);
}
extern void destroyOptimizedBuffer(BufferPtr buffer);
extern uint32_t getBufferWidth(BufferPtr buffer);
extern uint32_t getBufferHeight(BufferPtr buffer);

extern void bufferClear(BufferPtr buffer, const float* bg);
extern void bufferDrawText(BufferPtr buffer, const uint8_t* text, size_t textLen, uint32_t x, uint32_t y, const float* fg, const float* bg, uint8_t attributes);
extern void bufferFillRect(BufferPtr buffer, uint32_t x, uint32_t y, uint32_t width, uint32_t height, const float* bg);

// Older global cursor functions (if present)
extern void setCursorPosition(int32_t x, int32_t y, bool visible);
extern void setCursorStyle(const uint8_t* style, size_t styleLen, bool blinking);
extern void setCursorColor(const float* color);

extern void clearTerminal(RendererPtr renderer);
extern void resizeRenderer(RendererPtr renderer, uint32_t width, uint32_t height);

// Newer Zig API symbol names we may probe at runtime (renderer-scoped)
typedef void (*fn_setCursorPosition_r)(RendererPtr, int32_t, int32_t, bool);
typedef void (*fn_setCursorStyle_r)(RendererPtr, const uint8_t*, size_t, bool);
typedef void (*fn_setCursorColor_r)(RendererPtr, const float*);
typedef void (*fn_enableMouse_r)(RendererPtr, bool);
typedef void (*fn_disableMouse_r)(RendererPtr);
typedef void (*fn_setRenderOffset_r)(RendererPtr, uint32_t);
typedef void (*fn_updateStats_r)(RendererPtr, double, uint32_t, double);
typedef void (*fn_updateMemoryStats_r)(RendererPtr, uint32_t, uint32_t, uint32_t);
typedef BufferPtr (*fn_createOptimizedBuffer2)(uint32_t, uint32_t, bool, uint8_t);
typedef void (*fn_bufferSetCellWithAlphaBlending)(BufferPtr, uint32_t, uint32_t, uint32_t, const float*, const float*, uint8_t);
typedef void (*fn_bufferDrawBox)(BufferPtr, int32_t, int32_t, uint32_t, uint32_t, const uint32_t*, uint32_t, const float*, const float*, const uint8_t*, uint32_t);
typedef void (*fn_drawFrameBuffer)(BufferPtr, int32_t, int32_t, BufferPtr, uint32_t, uint32_t, uint32_t, uint32_t);
typedef void (*fn_bufferDrawPackedBuffer)(BufferPtr, const uint8_t*, size_t, uint32_t, uint32_t, uint32_t, uint32_t);
typedef void (*fn_bufferDrawSuperSampleBuffer)(BufferPtr, uint32_t, uint32_t, const uint8_t*, size_t, uint8_t, uint32_t);

static void* sym(const char* name) {
#if defined(__APPLE__) || defined(__linux__)
    return dlsym(RTLD_DEFAULT, name);
#elif defined(_WIN32)
    // Try main module first, then all loaded modules
    void* p = (void*)GetProcAddress(GetModuleHandle(NULL), name);
    if (!p) {
        // Also search in all loaded DLLs
        HMODULE hMod = NULL;
        if (GetModuleHandleEx(
                GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                (LPCSTR)&sym, &hMod) && hMod) {
            p = (void*)GetProcAddress(hMod, name);
        }
    }
    return p;
#else
    (void)name; return NULL;
#endif
}

static void to_float4(const double* in, float out[4]) {
    for (int i = 0; i < 4; i++) out[i] = (float)in[i];
}

// Simple wrappers that MoonBit can call more easily

// Note: MoonBit passes FixedArray[Double] which we receive as double*
// We need to convert to float* for the Zig library

void setBackgroundColorMB(RendererPtr renderer, const double* color) {
    float fcolor[4];
    for (int i = 0; i < 4; i++) {
        fcolor[i] = (float)color[i];
    }
    setBackgroundColor(renderer, fcolor);
}

void bufferClearMB(BufferPtr buffer, const double* bg) {
    float fbg[4];
    for (int i = 0; i < 4; i++) {
        fbg[i] = (float)bg[i];
    }
    bufferClear(buffer, fbg);
}

void bufferDrawTextMB(BufferPtr buffer, const uint8_t* text, size_t textLen, uint32_t x, uint32_t y, const double* fg, const double* bg, uint8_t attributes) {
    float ffg[4];
    for (int i = 0; i < 4; i++) {
        ffg[i] = (float)fg[i];
    }
    
    float fbg[4];
    for (int i = 0; i < 4; i++) {
        fbg[i] = (float)bg[i];
    }
    
    bufferDrawText(buffer, text, textLen, x, y, ffg, fbg, attributes);
}

void bufferDrawTextNoBgMB(BufferPtr buffer, const uint8_t* text, size_t textLen, uint32_t x, uint32_t y, const double* fg, uint8_t attributes) {
    float ffg[4];
    for (int i = 0; i < 4; i++) {
        ffg[i] = (float)fg[i];
    }
    
    bufferDrawText(buffer, text, textLen, x, y, ffg, NULL, attributes);
}

void bufferFillRectMB(BufferPtr buffer, uint32_t x, uint32_t y, uint32_t width, uint32_t height, const double* bg) {
    float fbg[4];
    for (int i = 0; i < 4; i++) {
        fbg[i] = (float)bg[i];
    }
    bufferFillRect(buffer, x, y, width, height, fbg);
}

void setCursorColorMB(const double* color) {
    float fcolor[4];
    to_float4(color, fcolor);
    setCursorColor(fcolor);
}

// Renderer-scoped cursor control (adapts to old global symbols if needed)
void setCursorPositionRMB(RendererPtr renderer, int32_t x, int32_t y, bool visible) {
    fn_setCursorPosition_r f = (fn_setCursorPosition_r)sym("setCursorPosition");
    if (f) {
        f(renderer, x, y, visible);
    } else {
        // fallback to old global function
        setCursorPosition(x, y, visible);
    }
}

void setCursorStyleRMB(RendererPtr renderer, const uint8_t* style, size_t styleLen, bool blinking) {
    fn_setCursorStyle_r f = (fn_setCursorStyle_r)sym("setCursorStyle");
    if (f) {
        f(renderer, style, styleLen, blinking);
    } else {
        setCursorStyle(style, styleLen, blinking);
    }
}

void setCursorColorRMB(RendererPtr renderer, const double* color) {
    float fcolor[4];
    to_float4(color, fcolor);
    fn_setCursorColor_r f = (fn_setCursorColor_r)sym("setCursorColor");
    if (f) {
        f(renderer, fcolor);
    } else {
        setCursorColor(fcolor);
    }
}

// Renderer control additions
void enableMouseR(RendererPtr renderer, bool enableMovement) {
    fn_enableMouse_r f = (fn_enableMouse_r)sym("enableMouse");
    if (f) f(renderer, enableMovement);
}

void disableMouseR(RendererPtr renderer) {
    fn_disableMouse_r f = (fn_disableMouse_r)sym("disableMouse");
    if (f) f(renderer);
}

void setRenderOffsetR(RendererPtr renderer, uint32_t offset) {
    fn_setRenderOffset_r f = (fn_setRenderOffset_r)sym("setRenderOffset");
    if (f) f(renderer, offset);
}

void updateStatsR(RendererPtr renderer, double time, uint32_t fps, double frameCallbackTime) {
    fn_updateStats_r f = (fn_updateStats_r)sym("updateStats");
    if (f) f(renderer, time, fps, frameCallbackTime);
}

void updateMemoryStatsR(RendererPtr renderer, uint32_t heapUsed, uint32_t heapTotal, uint32_t arrayBuffers) {
    fn_updateMemoryStats_r f = (fn_updateMemoryStats_r)sym("updateMemoryStats");
    if (f) f(renderer, heapUsed, heapTotal, arrayBuffers);
}

// Enhanced buffer creation with width method (fallback to older)
BufferPtr createOptimizedBuffer2(uint32_t width, uint32_t height, bool respectAlpha, uint8_t widthMethod) {
    // The new Zig API needs an id string - just pass empty string for now
    const char* empty_id = "";
    return createOptimizedBuffer(width, height, respectAlpha, widthMethod, (const uint8_t*)empty_id, 0);
}

void bufferSetCellWithAlphaBlendingMB(BufferPtr buffer, uint32_t x, uint32_t y, uint32_t char_code, const double* fg, const double* bg, uint8_t attributes) {
    float ffg[4]; float fbg[4];
    to_float4(fg, ffg); to_float4(bg, fbg);
#if defined(_WIN32)
    // Direct cell write on Windows (no Zig library)
    extern void stubSetCellWithAlpha(void* buf, uint32_t x, uint32_t y, uint32_t cp, const float* fg, const float* bg, uint8_t attrs);
    stubSetCellWithAlpha(buffer, x, y, char_code, ffg, fbg, attributes);
#else
    fn_bufferSetCellWithAlphaBlending f = (fn_bufferSetCellWithAlphaBlending)sym("bufferSetCellWithAlphaBlending");
    if (f) f(buffer, x, y, char_code, ffg, fbg, attributes);
#endif
}

void bufferDrawBoxMB(BufferPtr buffer, int32_t x, int32_t y, uint32_t width, uint32_t height, const uint32_t* borderChars, uint32_t packedOptions, const double* borderColor, const double* backgroundColor, const uint8_t* title, uint32_t titleLen) {
    float fborder[4]; float fbg[4];
    to_float4(borderColor, fborder); to_float4(backgroundColor, fbg);
#if defined(_WIN32)
    // Direct implementation on Windows (no Zig library available)
    extern void stubSetCellWithAlpha(void* buf, uint32_t x, uint32_t y, uint32_t cp, const float* fg, const float* bg, uint8_t attrs);
    if (width < 2 || height < 2) return;
    if (x < 0 || y < 0) return;

    // borderChars layout: [topLeft, topRight, bottomLeft, bottomRight, hLine, vLine]
    uint32_t tl = borderChars ? borderChars[0] : 0x250C;
    uint32_t tr = borderChars ? borderChars[1] : 0x2510;
    uint32_t bl = borderChars ? borderChars[2] : 0x2514;
    uint32_t br = borderChars ? borderChars[3] : 0x2518;
    uint32_t hz = borderChars ? borderChars[4] : 0x2500;
    uint32_t vt = borderChars ? borderChars[5] : 0x2502;

    // Top-left corner
    stubSetCellWithAlpha(buffer, (uint32_t)x, (uint32_t)y, tl, fborder, fbg, 0);
    // Top edge
    for (uint32_t i = 1; i < width - 1; i++)
        stubSetCellWithAlpha(buffer, (uint32_t)x + i, (uint32_t)y, hz, fborder, fbg, 0);
    // Top-right corner
    stubSetCellWithAlpha(buffer, (uint32_t)x + width - 1, (uint32_t)y, tr, fborder, fbg, 0);

    // Left and right edges
    for (uint32_t j = 1; j < height - 1; j++) {
        stubSetCellWithAlpha(buffer, (uint32_t)x, (uint32_t)y + j, vt, fborder, fbg, 0);
        stubSetCellWithAlpha(buffer, (uint32_t)x + width - 1, (uint32_t)y + j, vt, fborder, fbg, 0);
    }

    // Bottom-left corner
    stubSetCellWithAlpha(buffer, (uint32_t)x, (uint32_t)y + height - 1, bl, fborder, fbg, 0);
    // Bottom edge
    for (uint32_t i = 1; i < width - 1; i++)
        stubSetCellWithAlpha(buffer, (uint32_t)x + i, (uint32_t)y + height - 1, hz, fborder, fbg, 0);
    // Bottom-right corner
    stubSetCellWithAlpha(buffer, (uint32_t)x + width - 1, (uint32_t)y + height - 1, br, fborder, fbg, 0);

    // Draw title on top edge (starting at x+1)
    if (title && titleLen > 0) {
        extern int stubWriteUtf8Text(void* buf, uint32_t start_x, uint32_t cy, const uint8_t* text, size_t len, uint32_t max_cells, const float* fg, const float* bg, uint8_t attrs);
        stubWriteUtf8Text(buffer, (uint32_t)x + 1, (uint32_t)y, title, titleLen, width - 2, fborder, fbg, 0);
    }
#else
    fn_bufferDrawBox f = (fn_bufferDrawBox)sym("bufferDrawBox");
    if (f) f(buffer, x, y, width, height, borderChars, packedOptions, fborder, fbg, title, titleLen);
#endif
}

void drawFrameBufferR(BufferPtr target, int32_t destX, int32_t destY, BufferPtr frameBuffer, uint32_t sourceX, uint32_t sourceY, uint32_t sourceWidth, uint32_t sourceHeight) {
    fn_drawFrameBuffer f = (fn_drawFrameBuffer)sym("drawFrameBuffer");
    if (f) f(target, destX, destY, frameBuffer, sourceX, sourceY, sourceWidth, sourceHeight);
}

void bufferDrawPackedBufferR(BufferPtr buffer, const uint8_t* data, uint32_t dataLen, uint32_t posX, uint32_t posY, uint32_t terminalWidthCells, uint32_t terminalHeightCells) {
    fn_bufferDrawPackedBuffer f = (fn_bufferDrawPackedBuffer)sym("bufferDrawPackedBuffer");
    if (f) f(buffer, data, (size_t)dataLen, posX, posY, terminalWidthCells, terminalHeightCells);
}

void bufferDrawSuperSampleBufferR(BufferPtr buffer, uint32_t x, uint32_t y, const uint8_t* pixelData, uint32_t len, uint8_t format, uint32_t alignedBytesPerRow) {
    fn_bufferDrawSuperSampleBuffer f = (fn_bufferDrawSuperSampleBuffer)sym("bufferDrawSuperSampleBuffer");
    if (f) f(buffer, x, y, pixelData, (size_t)len, format, alignedBytesPerRow);
}

// ============================================================================
// Terminal input handling functions — cross-platform (POSIX + Windows)
// ============================================================================

#if defined(_WIN32)
// ---- Windows Console API implementation ----
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <conio.h>

static DWORD orig_console_mode = 0;
static bool raw_mode_enabled = false;
static HANDLE h_stdin = INVALID_HANDLE_VALUE;
static HANDLE h_stdout = INVALID_HANDLE_VALUE;
static uint32_t last_width = 0;
static uint32_t last_height = 0;

// Enable virtual terminal processing on stdout (for ANSI escape sequences)
static void enable_vt_processing(HANDLE h) {
    DWORD mode = 0;
    if (GetConsoleMode(h, &mode)) {
        mode |= ENABLE_VIRTUAL_TERMINAL_PROCESSING;
        SetConsoleMode(h, mode);
    }
}

// Set terminal to raw mode for keyboard input (Windows version)
int setTerminalRawMode() {
    if (raw_mode_enabled) return 0;

    h_stdin = GetStdHandle(STD_INPUT_HANDLE);
    h_stdout = GetStdHandle(STD_OUTPUT_HANDLE);

    if (h_stdin == INVALID_HANDLE_VALUE) return -1;

    if (!GetConsoleMode(h_stdin, &orig_console_mode)) {
        // Not a console — OK for rendering-only mode
        return -1;
    }

    // Disable line input, echo, Ctrl+C processing, and window input
    DWORD new_mode = orig_console_mode;
    new_mode &= ~(ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT |
                  ENABLE_PROCESSED_INPUT | ENABLE_WINDOW_INPUT);
    // Enable virtual terminal input for ANSI key sequences
    new_mode |= ENABLE_VIRTUAL_TERMINAL_INPUT;

    if (!SetConsoleMode(h_stdin, new_mode)) {
        return -1;
    }

    // Enable VT processing on stdout for ANSI rendering
    if (h_stdout != INVALID_HANDLE_VALUE) {
        enable_vt_processing(h_stdout);
    }

    // Set stdin to UTF-8 for proper Unicode handling
    SetConsoleCP(CP_UTF8);
    SetConsoleOutputCP(CP_UTF8);

    // Record initial terminal size for resize detection
    CONSOLE_SCREEN_BUFFER_INFO csbi;
    if (GetConsoleScreenBufferInfo(h_stdout, &csbi)) {
        last_width = (uint32_t)(csbi.srWindow.Right - csbi.srWindow.Left + 1);
        last_height = (uint32_t)(csbi.srWindow.Bottom - csbi.srWindow.Top + 1);
    }

    raw_mode_enabled = true;
    return 0;
}

// Restore terminal to normal mode (Windows version)
int restoreTerminalMode() {
    if (!raw_mode_enabled) return 0;

    if (h_stdin != INVALID_HANDLE_VALUE) {
        SetConsoleMode(h_stdin, orig_console_mode);
    }

    raw_mode_enabled = false;
    return 0;
}

// Read a single byte from stdin (non-blocking, Windows version)
// Returns -1 if no data available, -2 on error, or the byte value (0-255)
// Extended keys are buffered internally to emit complete CSI sequences.
static uint8_t key_buf[32];
static int key_buf_pos = 0;
static int key_buf_len = 0;

int readKeyByte() {
    // Return buffered bytes first
    if (key_buf_pos < key_buf_len) {
        return (int)key_buf[key_buf_pos++];
    }
    key_buf_pos = 0;
    key_buf_len = 0;

    if (!_kbhit()) return -1;

    int c = _getch();
    if (c == EOF) return -2;

    // Handle extended keys: _getch() returns 0x00 or 0xE0 prefix for special keys
    if (c == 0 || c == 0xE0) {
        int code = _getch();
        key_buf[0] = 27;   // ESC
        key_buf[1] = '[';
        switch (code) {
            case 72: key_buf[2] = 'A'; key_buf_len = 3; break;  // Up
            case 80: key_buf[2] = 'B'; key_buf_len = 3; break;  // Down
            case 77: key_buf[2] = 'C'; key_buf_len = 3; break;  // Right
            case 75: key_buf[2] = 'D'; key_buf_len = 3; break;  // Left
            case 71: key_buf[2] = 'H'; key_buf_len = 3; break;  // Home
            case 79: key_buf[2] = 'F'; key_buf_len = 3; break;  // End
            case 82: // Insert
                key_buf[2] = '2'; key_buf[3] = '~'; key_buf_len = 4; break;
            case 83: // Delete
                key_buf[2] = '3'; key_buf[3] = '~'; key_buf_len = 4; break;
            case 73: // PageUp
                key_buf[2] = '5'; key_buf[3] = '~'; key_buf_len = 4; break;
            case 81: // PageDown
                key_buf[2] = '6'; key_buf[3] = '~'; key_buf_len = 4; break;
            case 59: // F1
                key_buf[2] = '1'; key_buf[3] = '1'; key_buf[4] = 'P'; key_buf_len = 5; break;
            case 60: // F2
                key_buf[2] = '1'; key_buf[3] = '2'; key_buf[4] = '~'; key_buf_len = 5; break;
            case 61: // F3
                key_buf[2] = '1'; key_buf[3] = '3'; key_buf[4] = '~'; key_buf_len = 5; break;
            case 62: // F4
                key_buf[2] = '1'; key_buf[3] = '4'; key_buf[4] = '~'; key_buf_len = 5; break;
            case 63: // F5
                key_buf[2] = '1'; key_buf[3] = '5'; key_buf[4] = '~'; key_buf_len = 5; break;
            case 64: // F6
                key_buf[2] = '1'; key_buf[3] = '7'; key_buf[4] = '~'; key_buf_len = 5; break;
            case 65: // F7
                key_buf[2] = '1'; key_buf[3] = '8'; key_buf[4] = '~'; key_buf_len = 5; break;
            case 66: // F8
                key_buf[2] = '1'; key_buf[3] = '9'; key_buf[4] = '~'; key_buf_len = 5; break;
            case 67: // F9
                key_buf[2] = '2'; key_buf[3] = '0'; key_buf[4] = '~'; key_buf_len = 5; break;
            case 68: // F10
                key_buf[2] = '2'; key_buf[3] = '1'; key_buf[4] = '~'; key_buf_len = 5; break;
            case 133: // F11
                key_buf[2] = '2'; key_buf[3] = '3'; key_buf[4] = '~'; key_buf_len = 5; break;
            case 134: // F12
                key_buf[2] = '2'; key_buf[3] = '4'; key_buf[4] = '~'; key_buf_len = 5; break;
            default: // Unknown extended key - silently discard
                key_buf_len = 0;
                return -1;
        }
        return (int)key_buf[key_buf_pos++];
    }

    return (int)(uint8_t)c;
}

// Get terminal size (Windows version)
void getTerminalSize(uint32_t* width, uint32_t* height) {
    HANDLE h = GetStdHandle(STD_OUTPUT_HANDLE);
    if (h != INVALID_HANDLE_VALUE) {
        CONSOLE_SCREEN_BUFFER_INFO csbi;
        if (GetConsoleScreenBufferInfo(h, &csbi)) {
            *width = (uint32_t)(csbi.srWindow.Right - csbi.srWindow.Left + 1);
            *height = (uint32_t)(csbi.srWindow.Bottom - csbi.srWindow.Top + 1);
            if (*width > 0 && *height > 0) return;
        }
    }

    // Default fallback
    *width = 80;
    *height = 24;
}

// Check if input is available (non-blocking, Windows version)
bool isInputAvailable() {
    return _kbhit() != 0;
}

// Resize detection via polling (Windows has no SIGWINCH equivalent)
static volatile int terminal_resized = 0;

// Install resize handler (Windows version — uses polling instead of signals)
int installResizeHandler() {
    // On Windows, we detect resize by polling console size in wasTerminalResized()
    // No signal handler needed
    CONSOLE_SCREEN_BUFFER_INFO csbi;
    HANDLE h = GetStdHandle(STD_OUTPUT_HANDLE);
    if (h != INVALID_HANDLE_VALUE && GetConsoleScreenBufferInfo(h, &csbi)) {
        last_width = (uint32_t)(csbi.srWindow.Right - csbi.srWindow.Left + 1);
        last_height = (uint32_t)(csbi.srWindow.Bottom - csbi.srWindow.Top + 1);
    }
    return 0;
}

// Check if terminal was resized (Windows version — polling-based)
bool wasTerminalResized() {
    HANDLE h = GetStdHandle(STD_OUTPUT_HANDLE);
    if (h != INVALID_HANDLE_VALUE) {
        CONSOLE_SCREEN_BUFFER_INFO csbi;
        if (GetConsoleScreenBufferInfo(h, &csbi)) {
            uint32_t w = (uint32_t)(csbi.srWindow.Right - csbi.srWindow.Left + 1);
            uint32_t hh = (uint32_t)(csbi.srWindow.Bottom - csbi.srWindow.Top + 1);
            if (w != last_width || hh != last_height) {
                last_width = w;
                last_height = hh;
                return true;
            }
        }
    }
    return false;
}

// Enable mouse tracking via ANSI escape sequences (works on Windows Terminal / ConPTY)
void enableMouseTracking(bool track_movement) {
    if (track_movement) {
        printf("\033[?1003h");
    } else {
        printf("\033[?1000h");
    }
    printf("\033[?1006h");
    fflush(stdout);
}

// Disable mouse tracking
void disableMouseTracking() {
    printf("\033[?1003l");
    printf("\033[?1000l");
    printf("\033[?1006l");
    fflush(stdout);
}

// Sleep for given milliseconds (Windows version)
void sleepMs(int milliseconds) {
    Sleep((DWORD)milliseconds);
}

#else
// ---- POSIX implementation (macOS / Linux) ----
#include <termios.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <fcntl.h>
#include <errno.h>
#include <signal.h>
#include <poll.h>

static struct termios orig_termios;
static bool raw_mode_enabled = false;
static int tty_fd = -1;

// Set terminal to raw mode for keyboard input
int setTerminalRawMode() {
    if (raw_mode_enabled) return 0;

    int fd = STDIN_FILENO;
    if (!isatty(fd)) {
        tty_fd = open("/dev/tty", O_RDWR);
        if (tty_fd == -1) return -1;
        fd = tty_fd;
    }

    if (tcgetattr(fd, &orig_termios) == -1) {
        if (tty_fd != -1) { close(tty_fd); tty_fd = -1; }
        return -1;
    }

    struct termios raw = orig_termios;
    raw.c_iflag &= ~(BRKINT | ICRNL | INPCK | ISTRIP | IXON);
    raw.c_oflag &= ~(OPOST);
    raw.c_cflag |= (CS8);
    raw.c_lflag &= ~(ECHO | ICANON | IEXTEN | ISIG);
    raw.c_cc[VMIN] = 0;
    raw.c_cc[VTIME] = 1;

    if (tcsetattr(fd, TCSAFLUSH, &raw) == -1) {
        if (tty_fd != -1) { close(tty_fd); tty_fd = -1; }
        return -1;
    }

    raw_mode_enabled = true;
    return 0;
}

// Restore terminal to normal mode
int restoreTerminalMode() {
    if (!raw_mode_enabled) return 0;
    int fd = (tty_fd != -1) ? tty_fd : STDIN_FILENO;
    if (tcsetattr(fd, TCSAFLUSH, &orig_termios) == -1) return -1;
    if (tty_fd != -1) { close(tty_fd); tty_fd = -1; }
    raw_mode_enabled = false;
    return 0;
}

// Read a single byte from stdin (non-blocking via poll)
int readKeyByte() {
    uint8_t c;
    int fd = (tty_fd != -1) ? tty_fd : STDIN_FILENO;

    // Use poll() with a short timeout instead of relying on VTIME,
    // which does not work correctly on WSL/PTY environments.
    struct pollfd pfd;
    pfd.fd = fd;
    pfd.events = POLLIN;
    pfd.revents = 0;
    int pr = poll(&pfd, 1, 50); // 50ms timeout
    if (pr <= 0) return -1;     // timeout or error → no input

    int nread = read(fd, &c, 1);
    if (nread == -1) {
        if (errno == EAGAIN || errno == EWOULDBLOCK) return -1;
        return -2;
    } else if (nread == 0) {
        return -1;
    }
    return (int)c;
}

// Get terminal size
void getTerminalSize(uint32_t* width, uint32_t* height) {
    struct winsize ws;
    if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0 && ws.ws_col > 0) {
        *width = ws.ws_col;
        *height = ws.ws_row;
        return;
    }
    int tty = open("/dev/tty", O_RDWR);
    if (tty != -1) {
        int result = ioctl(tty, TIOCGWINSZ, &ws);
        close(tty);
        if (result == 0 && ws.ws_col > 0) {
            *width = ws.ws_col;
            *height = ws.ws_row;
            return;
        }
    }
    *width = 80;
    *height = 24;
}

// Check if input is available (non-blocking)
bool isInputAvailable() {
    int fd = (tty_fd != -1) ? tty_fd : STDIN_FILENO;
    int oldf = fcntl(fd, F_GETFL, 0);
    fcntl(fd, F_SETFL, oldf | O_NONBLOCK);
    uint8_t c;
    int result = read(fd, &c, 1);
    if (result == 1) {
        if (tty_fd != -1) {
            fcntl(fd, F_SETFL, oldf);
            return true;
        } else {
            ungetc(c, stdin);
        }
        fcntl(fd, F_SETFL, oldf);
        return true;
    }
    fcntl(fd, F_SETFL, oldf);
    return false;
}

// Signal handling for terminal resize
static volatile sig_atomic_t terminal_resized = 0;
static void (*resize_callback)(uint32_t, uint32_t) = NULL;

static void handle_winch(int sig) {
    (void)sig;
    terminal_resized = 1;
}

int installResizeHandler() {
    struct sigaction sa;
    sa.sa_handler = handle_winch;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = 0;
    if (sigaction(SIGWINCH, &sa, NULL) == -1) return -1;
    return 0;
}

bool wasTerminalResized() {
    if (terminal_resized) {
        terminal_resized = 0;
        return true;
    }
    return false;
}

void enableMouseTracking(bool track_movement) {
    if (track_movement) {
        printf("\033[?1003h");
    } else {
        printf("\033[?1000h");
    }
    printf("\033[?1006h");
    fflush(stdout);
}

void disableMouseTracking() {
    printf("\033[?1003l");
    printf("\033[?1000l");
    printf("\033[?1006l");
    fflush(stdout);
}

void sleepMs(int milliseconds) {
    usleep(milliseconds * 1000);
}

#endif // _WIN32

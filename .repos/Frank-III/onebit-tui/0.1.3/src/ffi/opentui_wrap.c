// C wrapper for OpenTUI Zig library
// This wrapper provides a simpler interface for MoonBit FFI and adapts
// across evolving Zig exports by probing symbols at runtime when needed.

#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <stddef.h>
#include <stdio.h>
#if defined(__APPLE__) || defined(__linux__)
#include <dlfcn.h>
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
    
    // Enhanced debug output
    static int call_count = 0;
    if (call_count < 20) {
        FILE* f = fopen("/tmp/moonbit_text_debug.txt", "a");
        if (f) {
            fprintf(f, "Call %d: pos=(%u,%u) len=%zu text='", call_count, x, y, textLen);
            for (size_t i = 0; i < textLen; i++) {
                if (text[i] >= 32 && text[i] < 127) {
                    fprintf(f, "%c", text[i]);
                } else {
                    fprintf(f, "[%02x]", text[i]);
                }
            }
            fprintf(f, "' bytes=");
            for (size_t i = 0; i < textLen && i < 10; i++) {
                fprintf(f, "%02x ", text[i]);
            }
            fprintf(f, "\n");
            fclose(f);
        }
    }
    call_count++;
    
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
    fn_bufferSetCellWithAlphaBlending f = (fn_bufferSetCellWithAlphaBlending)sym("bufferSetCellWithAlphaBlending");
    if (f) f(buffer, x, y, char_code, ffg, fbg, attributes);
}

void bufferDrawBoxMB(BufferPtr buffer, int32_t x, int32_t y, uint32_t width, uint32_t height, const uint32_t* borderChars, uint32_t packedOptions, const double* borderColor, const double* backgroundColor, const uint8_t* title, uint32_t titleLen) {
    float fborder[4]; float fbg[4];
    to_float4(borderColor, fborder); to_float4(backgroundColor, fbg);
    fn_bufferDrawBox f = (fn_bufferDrawBox)sym("bufferDrawBox");
    if (f) f(buffer, x, y, width, height, borderChars, packedOptions, fborder, fbg, title, titleLen);
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

// Terminal input handling functions
#include <termios.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <fcntl.h>
#include <errno.h>

static struct termios orig_termios;
static bool raw_mode_enabled = false;
static int tty_fd = -1;

// Set terminal to raw mode for keyboard input
int setTerminalRawMode() {
    if (raw_mode_enabled) return 0;
    
    // First try to use stdin if it's a TTY
    int fd = STDIN_FILENO;
    if (!isatty(fd)) {
        // If stdin is not a TTY, try to open /dev/tty directly
        tty_fd = open("/dev/tty", O_RDWR);
        if (tty_fd == -1) {
            // No TTY available at all - this is OK for rendering-only mode
            return -1;
        }
        fd = tty_fd;
    }
    
    if (tcgetattr(fd, &orig_termios) == -1) {
        if (tty_fd != -1) {
            close(tty_fd);
            tty_fd = -1;
        }
        return -1;
    }
    
    struct termios raw = orig_termios;
    raw.c_iflag &= ~(BRKINT | ICRNL | INPCK | ISTRIP | IXON);
    raw.c_oflag &= ~(OPOST);
    raw.c_cflag |= (CS8);
    raw.c_lflag &= ~(ECHO | ICANON | IEXTEN | ISIG);
    raw.c_cc[VMIN] = 0;  // Non-blocking read
    raw.c_cc[VTIME] = 1; // 100ms timeout
    
    if (tcsetattr(fd, TCSAFLUSH, &raw) == -1) {
        if (tty_fd != -1) {
            close(tty_fd);
            tty_fd = -1;
        }
        return -1;
    }
    
    raw_mode_enabled = true;
    return 0;
}

// Restore terminal to normal mode
int restoreTerminalMode() {
    if (!raw_mode_enabled) return 0;
    
    int fd = (tty_fd != -1) ? tty_fd : STDIN_FILENO;
    
    if (tcsetattr(fd, TCSAFLUSH, &orig_termios) == -1) {
        return -1;
    }
    
    if (tty_fd != -1) {
        close(tty_fd);
        tty_fd = -1;
    }
    
    raw_mode_enabled = false;
    return 0;
}

// Read a single byte from stdin (non-blocking)
// Returns -1 if no data available, -2 on error, or the byte value (0-255)
int readKeyByte() {
    uint8_t c;
    int fd = (tty_fd != -1) ? tty_fd : STDIN_FILENO;
    int nread = read(fd, &c, 1);
    
    if (nread == -1) {
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            return -1; // No data available
        }
        return -2; // Error
    } else if (nread == 0) {
        return -1; // No data available
    }
    
    return (int)c;
}

// Get terminal size
void getTerminalSize(uint32_t* width, uint32_t* height) {
    struct winsize ws;
    
    // First try stdout
    if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0 && ws.ws_col > 0) {
        *width = ws.ws_col;
        *height = ws.ws_row;
        return;
    }
    
    // If stdout fails, try /dev/tty
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
    
    // Default fallback
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
        // For tty_fd we can't use ungetc, so we'll need a different approach
        // For now, just report that input is available
        if (tty_fd != -1) {
            // We read a byte but can't put it back easily
            // This is a limitation of this approach
            fcntl(fd, F_SETFL, oldf);
            return true;
        } else {
            // Put the character back for stdin
            ungetc(c, stdin);
        }
        fcntl(fd, F_SETFL, oldf);
        return true;
    }
    
    fcntl(fd, F_SETFL, oldf);
    return false;
}

// Signal handling for terminal resize
#include <signal.h>

static volatile sig_atomic_t terminal_resized = 0;
static void (*resize_callback)(uint32_t, uint32_t) = NULL;

// Signal handler for SIGWINCH
static void handle_winch(int sig) {
    (void)sig;
    terminal_resized = 1;
}

// Install resize signal handler
int installResizeHandler() {
    struct sigaction sa;
    sa.sa_handler = handle_winch;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = 0;
    
    if (sigaction(SIGWINCH, &sa, NULL) == -1) {
        return -1;
    }
    
    return 0;
}

// Check if terminal was resized
bool wasTerminalResized() {
    if (terminal_resized) {
        terminal_resized = 0;
        return true;
    }
    return false;
}

// Enable mouse tracking in terminal
void enableMouseTracking(bool track_movement) {
    // Enable mouse tracking
    if (track_movement) {
        // Track all mouse events including movement
        printf("\033[?1003h");
    } else {
        // Track only button events
        printf("\033[?1000h");
    }
    
    // Use SGR extended mouse mode for coordinates > 223
    printf("\033[?1006h");
    fflush(stdout);
}

// Disable mouse tracking
void disableMouseTracking() {
    printf("\033[?1003l");  // Disable all mouse tracking
    printf("\033[?1000l");  // Disable button tracking
    printf("\033[?1006l");  // Disable SGR mode
    fflush(stdout);
}

// Simple sleep function for event loop timing
void sleepMs(int milliseconds) {
    usleep(milliseconds * 1000);
}

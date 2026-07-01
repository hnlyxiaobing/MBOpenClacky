// OpenTUI ANSI rendering implementation for Windows / non-Zig platforms
// Replaces the Zig library with a pure ANSI-escape-code renderer.
// Input handling is in opentui_wrap.c (cross-platform _kbhit / termios).
//
// Architecture:
//   - Two frame buffers (A/B) for double-buffering.
//   - Each cell stores a UTF-8 encoded character + RGBA colours + attributes.
//   - render() writes the entire buffer row-by-row to stdout via ANSI SGR codes.
//   - A simple dirty-rect optimisation avoids redrawing unchanged rows.

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>

#ifdef _WIN32
#include <windows.h>
#endif

// Opaque pointer types (matching opentui_wrap.c definitions)
typedef void* RendererPtr;
typedef void* BufferPtr;

// ── Hit grid (mouse target registry) global state ─────────────────────

#define MAX_HIT_REGIONS 256
static struct { uint32_t x, y, w, h, id; } hit_grid[MAX_HIT_REGIONS];
static int hit_count = 0;

// ── Bridge: rename C system() to avoid symbol clash with MoonBit ──────

int32_t mb_system(const char* cmd) {
    return (int32_t)system(cmd);
}

// ── Curl stubs removed ─────────────────────────────────────────────────
// The original onebit-tui package provided no-op stubs for curl_easy_init,
// curl_easy_setopt, etc.  In ELF, a weak definition in the main executable
// shadows the strong definition in libcurl.so, so even with -lcurl linked
// the stubs were called and curl_easy_init() returned NULL.
// Stubs removed — libcurl is now linked directly (see lib/client/moon.pkg
// and cmd/moon.pkg cc-link-flags).

// ── types ──────────────────────────────────────────────────────────────

typedef struct Renderer Renderer;
typedef struct Buffer   Buffer;

// One cell on the grid — 16 bytes total, cache-friendly.
typedef struct {
    uint8_t  ch[8];      // UTF-8 encoded character (0-terminated)
    float    fg[4];      // RGBA foreground
    float    bg[4];      // RGBA background
    uint8_t  attrs;      // bit0=bold, bit3=underline
    bool     dirty;
} Cell;

#define MAX_SCISSOR_STACK 16

struct Buffer {
    uint32_t width;
    uint32_t height;
    Cell    *cells;       // width * height
    bool     owns_memory;
    // Scissor rect stack for clipping
    uint32_t scissor_x[MAX_SCISSOR_STACK];
    uint32_t scissor_y[MAX_SCISSOR_STACK];
    uint32_t scissor_w[MAX_SCISSOR_STACK];
    uint32_t scissor_h[MAX_SCISSOR_STACK];
    int      scissor_top; // stack depth (0 = no clipping)
};

struct Renderer {
    Buffer   buf[2];
    int      draw_idx;    // which buffer is being drawn to  (0 or 1)
    int      render_idx;  // which buffer was last rendered   (0 or 1)
    bool     first_frame;
    float    bg_color[4];
    // Cursor state
    int      cursor_x, cursor_y;
    bool     cursor_visible;
};

// ── helpers ────────────────────────────────────────────────────────────

static inline int imin(int a, int b) { return a < b ? a : b; }
static inline int imax(int a, int b) { return a > b ? a : b; }
static inline uint32_t umin(uint32_t a, uint32_t b) { return a < b ? a : b; }
static inline uint32_t umax(uint32_t a, uint32_t b) { return a > b ? a : b; }

static bool floats_equal(const float *a, const float *b) {
    return a[0] == b[0] && a[1] == b[1] && a[2] == b[2] && a[3] == b[3];
}

static void copy_floats(float *dst, const float *src) {
    dst[0] = src[0]; dst[1] = src[1]; dst[2] = src[2]; dst[3] = src[3];
}

// Write UTF-8 char from code point, return bytes written (1-4).
static int codepoint_to_utf8(uint32_t cp, uint8_t out[8]) {
    if (cp < 0x80) {
        out[0] = (uint8_t)cp; out[1] = 0; return 1;
    } else if (cp < 0x800) {
        out[0] = (uint8_t)(0xC0 | (cp >> 6));
        out[1] = (uint8_t)(0x80 | (cp & 0x3F));
        out[2] = 0; return 2;
    } else if (cp < 0x10000) {
        out[0] = (uint8_t)(0xE0 | (cp >> 12));
        out[1] = (uint8_t)(0x80 | ((cp >> 6) & 0x3F));
        out[2] = (uint8_t)(0x80 | (cp & 0x3F));
        out[3] = 0; return 3;
    } else {
        out[0] = (uint8_t)(0xF0 | (cp >> 18));
        out[1] = (uint8_t)(0x80 | ((cp >> 12) & 0x3F));
        out[2] = (uint8_t)(0x80 | ((cp >> 6) & 0x3F));
        out[3] = (uint8_t)(0x80 | (cp & 0x3F));
        out[4] = 0; return 4;
    }
}

// Decode a single UTF-8 character → code point. Returns bytes consumed (1-4).
static int utf8_codepoint(const uint8_t *s, size_t len, uint32_t *cp) {
    if (len == 0) { *cp = ' '; return 0; }
    uint8_t c = s[0];
    if (c < 0x80) { *cp = c; return 1; }
    if ((c & 0xE0) == 0xC0 && len >= 2) {
        *cp = ((uint32_t)(c & 0x1F) << 6) | (uint32_t)(s[1] & 0x3F);
        return 2;
    }
    if ((c & 0xF0) == 0xE0 && len >= 3) {
        *cp = ((uint32_t)(c & 0x0F) << 12) | ((uint32_t)(s[1] & 0x3F) << 6) | (uint32_t)(s[2] & 0x3F);
        return 3;
    }
    if ((c & 0xF8) == 0xF0 && len >= 4) {
        *cp = ((uint32_t)(c & 0x07) << 18) | ((uint32_t)(s[1] & 0x3F) << 12)
            | ((uint32_t)(s[2] & 0x3F) << 6)  | (uint32_t)(s[3] & 0x3F);
        return 4;
    }
    *cp = c; return 1;
}

// Determine the display width of a codepoint (CJK ≈ 2, ASCII ≈ 1).
static int char_width(uint32_t cp) {
    if (cp < 0x20)  return 0;   // control chars
    if (cp < 0x7F)  return 1;
    if (cp < 0xA0)  return 0;
    // CJK ranges (simplified)
    if ((cp >= 0x1100 && cp <= 0x115F) ||   // Hangul Jamo
        (cp >= 0x2E80 && cp <= 0xA4CF) ||   // CJK Radicals .. Yi
        (cp >= 0xAC00 && cp <= 0xD7A3) ||   // Hangul Syllables
        (cp >= 0xF900 && cp <= 0xFAFF) ||   // CJK Compatibility
        (cp >= 0xFE10 && cp <= 0xFE19) ||   // Vertical forms
        (cp >= 0xFE30 && cp <= 0xFE6F) ||   // CJK Compatibility Forms
        (cp >= 0xFF01 && cp <= 0xFF60) ||   // Fullwidth Forms
        (cp >= 0xFFE0 && cp <= 0xFFE6) ||   // Fullwidth Signs
        (cp >= 0x1F300 && cp <= 0x1F64F) || // Emoji
        (cp >= 0x20000 && cp <= 0x2FFFD) || // CJK Ext B+
        (cp >= 0x30000 && cp <= 0x3FFFD))   // CJK Ext C+
        return 2;
    return 1;
}

// ── buffer management ──────────────────────────────────────────────────

static Buffer* buf_alloc(uint32_t w, uint32_t h) {
    Buffer *b = (Buffer*)calloc(1, sizeof(Buffer));
    if (!b) return NULL;
    b->width  = w;
    b->height = h;
    b->cells  = (Cell*)calloc(w * h, sizeof(Cell));
    b->owns_memory = true;
    if (!b->cells) { free(b); return NULL; }
    // Initialise every cell to space with transparent black bg
    for (uint32_t i = 0; i < w * h; i++) {
        b->cells[i].ch[0] = ' ';
        b->cells[i].ch[1] = 0;
        b->cells[i].fg[0] = 1.0f; b->cells[i].fg[1] = 1.0f; b->cells[i].fg[2] = 1.0f; b->cells[i].fg[3] = 1.0f;
        b->cells[i].bg[0] = 0.0f; b->cells[i].bg[1] = 0.0f; b->cells[i].bg[2] = 0.0f; b->cells[i].bg[3] = 0.0f;
        b->cells[i].dirty = true;
    }
    return b;
}

static void buf_free(Buffer *b) {
    if (b && b->owns_memory) {
        free(b->cells);
        free(b);
    }
}

static Cell* buf_cell(Buffer *b, uint32_t x, uint32_t y) {
    if (!b || x >= b->width || y >= b->height) return NULL;
    return &b->cells[y * b->width + x];
}

// Check if (x, y) is within the current scissor rect (top of stack)
static bool buf_visible(Buffer *b, uint32_t x, uint32_t y) {
    if (!b || b->scissor_top <= 0) return true;
    int top = b->scissor_top - 1;
    uint32_t sx = b->scissor_x[top];
    uint32_t sy = b->scissor_y[top];
    uint32_t sw = b->scissor_w[top];
    uint32_t sh = b->scissor_h[top];
    return x >= sx && x < sx + sw && y >= sy && y < sy + sh;
}

// ── Renderer lifecycle ─────────────────────────────────────────────────

RendererPtr createRenderer(uint32_t width, uint32_t height, bool testing) {
    (void)testing;
    Renderer *r = (Renderer*)calloc(1, sizeof(Renderer));
    if (!r) return NULL;

    // Pre-allocate both buffers at creation time.
    // We use placement-initialisation via buf_alloc + memcpy.
    Buffer *a = buf_alloc(width, height);
    Buffer *b = buf_alloc(width, height);
    if (!a || !b) {
        buf_free(a); buf_free(b); free(r);
        return NULL;
    }
    memcpy(&r->buf[0], a, sizeof(Buffer)); free(a); // steal the allocation
    memcpy(&r->buf[1], b, sizeof(Buffer)); free(b);

    r->draw_idx   = 0;
    r->render_idx = 1;  // nothing rendered yet
    r->first_frame = true;
    r->bg_color[0] = 0.05f; r->bg_color[1] = 0.05f; r->bg_color[2] = 0.10f; r->bg_color[3] = 1.0f;
    r->cursor_x = -1; r->cursor_y = -1; r->cursor_visible = false;

#ifdef _WIN32
    // CRITICAL: Must enable VT processing BEFORE any ANSI escape sequences
    {
        HANDLE hOut = GetStdHandle(STD_OUTPUT_HANDLE);
        if (hOut != INVALID_HANDLE_VALUE) {
            DWORD mode = 0;
            if (GetConsoleMode(hOut, &mode)) {
                mode |= ENABLE_VIRTUAL_TERMINAL_PROCESSING;
                SetConsoleMode(hOut, mode);
                SetConsoleOutputCP(CP_UTF8);
                SetConsoleCP(CP_UTF8);
            }
        }
    }
#endif

    // Enter alternate screen, hide cursor
    fprintf(stdout, "\033[?1049h\033[?25l\033[2J\033[H");
    fflush(stdout);

    return (RendererPtr)r;
}

void destroyRenderer(RendererPtr renderer, bool useAlternateScreen, uint32_t splitHeight) {
    (void)splitHeight;
    Renderer *r = (Renderer*)renderer;
    if (!r) return;

    if (useAlternateScreen) {
        fprintf(stdout, "\033[?1049l");  // restore main screen
    }
    fprintf(stdout, "\033[?25h\033[0m"); // show cursor, reset SGR
    fflush(stdout);

    // Free cells only — buf[0]/buf[1] are embedded in Renderer, not heap-allocated
    if (r->buf[0].cells) {
        free(r->buf[0].cells);
        r->buf[0].cells = NULL;
        r->buf[0].owns_memory = false;
    }
    if (r->buf[1].cells) {
        free(r->buf[1].cells);
        r->buf[1].cells = NULL;
        r->buf[1].owns_memory = false;
    }
    free(r);
}

void setUseThread(RendererPtr renderer, bool useThread) {
    (void)renderer; (void)useThread;
}

void setBackgroundColor(RendererPtr renderer, const float* color) {
    Renderer *r = (Renderer*)renderer;
    if (r && color) copy_floats(r->bg_color, color);
}

// ── Buffer lifecycle ───────────────────────────────────────────────────

static uint32_t fallback_buf_w = 80, fallback_buf_h = 24;

BufferPtr getNextBuffer(RendererPtr renderer) {
    Renderer *r = (Renderer*)renderer;
    if (!r) return NULL;
    return (BufferPtr)&r->buf[r->draw_idx];
}

BufferPtr getCurrentBuffer(RendererPtr renderer) {
    Renderer *r = (Renderer*)renderer;
    if (!r) return NULL;
    return (BufferPtr)&r->buf[r->render_idx];
}

BufferPtr createOptimizedBuffer(uint32_t width, uint32_t height, bool respectAlpha,
                                 uint8_t widthMethod, const uint8_t* idPtr, size_t idLen) {
    (void)respectAlpha; (void)widthMethod; (void)idPtr; (void)idLen;
    fallback_buf_w = width;
    fallback_buf_h = height;
    Buffer *b = buf_alloc(width, height);
    return (BufferPtr)b;
}

void destroyOptimizedBuffer(BufferPtr buffer) {
    Buffer *b = (Buffer*)buffer;
    buf_free(b);
}

uint32_t getBufferWidth(BufferPtr buffer) {
    Buffer *b = (Buffer*)buffer;
    return b ? b->width : fallback_buf_w;
}

uint32_t getBufferHeight(BufferPtr buffer) {
    Buffer *b = (Buffer*)buffer;
    return b ? b->height : fallback_buf_h;
}

// ── Drawing ────────────────────────────────────────────────────────────

void bufferClear(BufferPtr buffer, const float* bg) {
    Buffer *b = (Buffer*)buffer;
    if (!b) return;
    for (uint32_t y = 0; y < b->height; y++) {
        for (uint32_t x = 0; x < b->width; x++) {
            Cell *c = buf_cell(b, x, y);
            c->ch[0] = ' '; c->ch[1] = 0;
            copy_floats(c->bg, bg);
            c->fg[0] = 1.0f; c->fg[1] = 1.0f; c->fg[2] = 1.0f; c->fg[3] = 1.0f;
            c->attrs = 0;
            c->dirty = true;
        }
    }
}

void bufferDrawText(BufferPtr buffer, const uint8_t* text, size_t textLen,
                    uint32_t x, uint32_t y, const float* fg, const float* bg, uint8_t attributes) {
    Buffer *b = (Buffer*)buffer;
    if (!b || !text || textLen == 0) return;

    uint32_t cx = x;
    uint32_t cy = y;
    size_t pos = 0;

    while (pos < textLen && cy < b->height) {
        uint32_t cp;
        int adv = utf8_codepoint(text + pos, textLen - pos, &cp);
        if (adv == 0) break;

        int w = char_width(cp);
        if (w == 0) { pos += adv; continue; }  // skip control chars

        // Clamp to buffer
        if (cx + (uint32_t)w > b->width) {
            // Wrap to next line (simple wrap, no word boundary)
            cx = 0;
            cy++;
            if (cy >= b->height) break;
        }

        Cell *c = buf_cell(b, cx, cy);
        if (c) {
            codepoint_to_utf8(cp, c->ch);
            if (fg) copy_floats(c->fg, fg);
            if (bg) copy_floats(c->bg, bg);
            c->attrs = attributes;
            c->dirty = true;
        }

        // For double-width chars, mark the next cell as continuation
        if (w == 2 && cx + 1 < b->width) {
            Cell *c2 = buf_cell(b, cx + 1, cy);
            if (c2) {
                c2->ch[0] = 0;  // zero-width continuation marker
                c2->ch[1] = 0;
                if (fg) copy_floats(c2->fg, fg);
                if (bg) copy_floats(c2->bg, bg);
                c2->attrs = attributes;
                c2->dirty = true;
            }
        }

        cx += (uint32_t)w;
        pos += (size_t)adv;
    }
}

void bufferFillRect(BufferPtr buffer, uint32_t x, uint32_t y,
                    uint32_t width, uint32_t height, const float* bg) {
    Buffer *b = (Buffer*)buffer;
    if (!b || !bg) return;
    uint32_t x2 = umin(x + width,  b->width);
    uint32_t y2 = umin(y + height, b->height);
    for (uint32_t row = y; row < y2; row++) {
        for (uint32_t col = x; col < x2; col++) {
            Cell *c = buf_cell(b, col, row);
            if (c) {
                copy_floats(c->bg, bg);
                c->dirty = true;
            }
        }
    }
}

// ── Helper functions for opentui_wrap.c (Windows box/cell drawing) ─────

void stubSetCellWithAlpha(void* buf, uint32_t x, uint32_t y, uint32_t cp,
                           const float* fg, const float* bg, uint8_t attrs) {
    Buffer *b = (Buffer*)buf;
    Cell *c = buf_cell(b, x, y);
    if (!c) return;
    codepoint_to_utf8(cp, c->ch);
    if (fg) copy_floats(c->fg, fg);
    if (bg) copy_floats(c->bg, bg);
    c->attrs = attrs;
    c->dirty = true;
}

// Write UTF-8 text into cells starting at (start_x, cy), up to max_cells wide.
// Returns number of cells consumed.
int stubWriteUtf8Text(void* buf, uint32_t start_x, uint32_t cy,
                       const uint8_t* text, size_t len, uint32_t max_cells,
                       const float* fg, const float* bg, uint8_t attrs) {
    Buffer *b = (Buffer*)buf;
    if (!b || !text || len == 0) return 0;
    uint32_t cx = start_x;
    size_t pos = 0;
    uint32_t cells_used = 0;
    while (pos < len && cells_used < max_cells && cx < b->width) {
        uint32_t cp;
        int adv = utf8_codepoint(text + pos, len - pos, &cp);
        if (adv == 0) break;
        int w = char_width(cp);
        if (w == 0) { pos += adv; continue; }
        Cell *c = buf_cell(b, cx, cy);
        if (c) {
            codepoint_to_utf8(cp, c->ch);
            if (fg) copy_floats(c->fg, fg);
            if (bg) copy_floats(c->bg, bg);
            c->attrs = attrs;
            c->dirty = true;
        }
        if (w == 2 && cx + 1 < b->width) {
            Cell *c2 = buf_cell(b, cx + 1, cy);
            if (c2) {
                c2->ch[0] = 0; c2->ch[1] = 0;
                if (fg) copy_floats(c2->fg, fg);
                if (bg) copy_floats(c2->bg, bg);
                c2->attrs = attrs;
                c2->dirty = true;
            }
        }
        cx += (uint32_t)w;
        pos += (size_t)adv;
        cells_used += (uint32_t)w;
    }
    return (int)cells_used;
}

// ── Render ─────────────────────────────────────────────────────────────

static void output_sgr(FILE *f, const float *fg, const float *bg, uint8_t attrs) {
    int fr = (int)(fg[0] * 255.0f);
    int fg_ = (int)(fg[1] * 255.0f);
    int fb = (int)(fg[2] * 255.0f);
    fprintf(f, "\033[38;2;%d;%d;%dm", fr, fg_, fb);

    if (bg && bg[3] > 0.001f) {
        int br = (int)(bg[0] * 255.0f);
        int bg_ = (int)(bg[1] * 255.0f);
        int bb = (int)(bg[2] * 255.0f);
        fprintf(f, "\033[48;2;%d;%d;%dm", br, bg_, bb);
    }

    if (attrs & 1)  fprintf(f, "\033[1m");   // bold
    if (attrs & 8)  fprintf(f, "\033[4m");   // underline
}

void render(RendererPtr renderer, bool force) {
    Renderer *r = (Renderer*)renderer;
    if (!r) return;

    // Reset hit grid for the new frame
    hit_count = 0;

    Buffer *src = &r->buf[r->draw_idx];   // what was just drawn
    Buffer *prev = r->first_frame ? NULL : &r->buf[r->render_idx];

    // On the FIRST frame, always do full redraw.
    bool full = force || r->first_frame;

    // Build output row-by-row.
    // For each row, check if ANY cell in that row is dirty (or full redraw).
    // If the row is clean, skip it entirely (cursor still advances via \n).

    FILE *f = stdout;

    // Cursor to home
    fputs("\033[H", f);

    for (uint32_t y = 0; y < src->height; y++) {
        // Quick dirty check for the whole row
        bool row_dirty = full;
        if (!row_dirty && prev) {
            for (uint32_t x = 0; x < src->width; x++) {
                if (src->cells[y * src->width + x].dirty) { row_dirty = true; break; }
            }
        }

        if (!row_dirty) {
            // Move cursor down one line without drawing
            fputs("\033[B", f);
            continue;
        }

        // Move to column 1 of this row
        fprintf(f, "\033[%d;1H\033[K", (int)(y + 1));

        const float *cur_fg = NULL;
        const float *cur_bg = NULL;
        uint8_t      cur_attrs = 0xFF;  // force first SGR

        for (uint32_t x = 0; x < src->width; x++) {
            Cell *c = &src->cells[y * src->width + x];

            // Skip zero-width continuation cells
            if (c->ch[0] == 0) continue;

            // Skip cells outside scissor rect
            if (!buf_visible(src, x, y)) continue;

            // If colours/attrs changed, emit SGR
            bool fg_changed = !cur_fg || !floats_equal(cur_fg, c->fg);
            bool bg_changed = !cur_bg || !floats_equal(cur_bg, c->bg);
            bool attr_changed = (cur_attrs != c->attrs);

            if (fg_changed || bg_changed || attr_changed) {
                fputs("\033[0m", f);  // reset
                output_sgr(f, c->fg, c->bg, c->attrs);
                cur_fg    = c->fg;
                cur_bg    = c->bg;
                cur_attrs = c->attrs;
            }

            fputs((const char*)c->ch, f);
            c->dirty = false;
        }
        fputs("\033[0m", f);  // reset at end of row
    }

    // Clear to end of screen (in case terminal is taller than buffer)
    fputs("\033[J", f);

    // Restore cursor if set
    if (r->cursor_visible && r->cursor_x >= 0 && r->cursor_y >= 0) {
        fprintf(f, "\033[%d;%dH\033[?25h", r->cursor_y + 1, r->cursor_x + 1);
    }

    fflush(f);

    // Swap buffers
    r->render_idx  = r->draw_idx;
    r->draw_idx    = 1 - r->draw_idx;
    r->first_frame = false;
}

void clearTerminal(RendererPtr renderer) {
    (void)renderer;
    fprintf(stdout, "\033[2J\033[H");
    fflush(stdout);
}

void resizeRenderer(RendererPtr renderer, uint32_t width, uint32_t height) {
    Renderer *r = (Renderer*)renderer;
    if (!r) return;
    // Free cells only — buf[0]/buf[1] are embedded in Renderer, not heap-allocated
    if (r->buf[0].cells) {
        free(r->buf[0].cells);
        r->buf[0].cells = NULL;
        r->buf[0].owns_memory = false;
    }
    if (r->buf[1].cells) {
        free(r->buf[1].cells);
        r->buf[1].cells = NULL;
        r->buf[1].owns_memory = false;
    }
    Buffer *a = buf_alloc(width, height);
    Buffer *b = buf_alloc(width, height);
    if (a && b) {
        memcpy(&r->buf[0], a, sizeof(Buffer)); free(a);
        memcpy(&r->buf[1], b, sizeof(Buffer)); free(b);
    }
    r->first_frame = true;
}

// ── Cursor ─────────────────────────────────────────────────────────────

void setCursorPosition(int32_t x, int32_t y, bool visible) {
    // During TUI rendering, cursor position is set via the renderer.
    // We store it and apply it at the end of render().
    // This global is shared — the renderer will pick it up.
    // (Simple approach: the last setCursorPosition call wins)
    extern void setCursorPositionRMB(void*, int32_t, int32_t, bool);
    // Actually this is handled in opentui_wrap.c → we just need the base.
    fprintf(stdout, "\033[%d;%dH", (int)(y + 1), (int)(x + 1));
    if (!visible) fprintf(stdout, "\033[?25l");
    else          fprintf(stdout, "\033[?25h");
    fflush(stdout);
}

void setCursorStyle(const uint8_t* style, size_t styleLen, bool blinking) {
    (void)style; (void)styleLen;
    fprintf(stdout, blinking ? "\033[1 q" : "\033[2 q");
    fflush(stdout);
}

void setCursorColor(const float* color) {
    if (!color) return;
    int r = (int)(color[0] * 255.0f);
    int g = (int)(color[1] * 255.0f);
    int b = (int)(color[2] * 255.0f);
    fprintf(stdout, "\033]12;#%02x%02x%02x\007", r, g, b);
    fflush(stdout);
}

// ── Hit grid (mouse target registry) ──────────────────────────────────

void addToHitGrid(BufferPtr buffer, uint32_t x, uint32_t y,
                  uint32_t width, uint32_t height, uint32_t id) {
    (void)buffer;
    if (hit_count < MAX_HIT_REGIONS) {
        hit_grid[hit_count].x = x; hit_grid[hit_count].y = y;
        hit_grid[hit_count].w = width; hit_grid[hit_count].h = height;
        hit_grid[hit_count].id = id;
        hit_count++;
    }
}

uint32_t checkHit(BufferPtr buffer, uint32_t x, uint32_t y) {
    (void)buffer;
    for (int i = hit_count - 1; i >= 0; i--) {
        if (x >= hit_grid[i].x && x < hit_grid[i].x + hit_grid[i].w &&
            y >= hit_grid[i].y && y < hit_grid[i].y + hit_grid[i].h) {
            return hit_grid[i].id;
        }
    }
    return 0;
}

void dumpHitGrid(BufferPtr buffer) {
    (void)buffer;
    hit_count = 0;  // reset on frame start (called by renderer)
}

// ── Scissor rect ───────────────────────────────────────────────────────

void bufferPushScissorRect(BufferPtr buffer, uint32_t x, uint32_t y,
                           uint32_t width, uint32_t height) {
    Buffer *b = (Buffer*)buffer;
    if (!b || b->scissor_top >= MAX_SCISSOR_STACK) return;
    int top = b->scissor_top;
    // Intersect with parent scissor rect if one exists
    if (top > 0) {
        int p = top - 1;
        uint32_t px = b->scissor_x[p], py = b->scissor_y[p];
        uint32_t pw = b->scissor_w[p], ph = b->scissor_h[p];
        uint32_t x2 = umin(x + width, px + pw);
        uint32_t y2 = umin(y + height, py + ph);
        x = umax(x, px);
        y = umax(y, py);
        width = (x2 > x) ? x2 - x : 0;
        height = (y2 > y) ? y2 - y : 0;
    }
    b->scissor_x[top] = x;
    b->scissor_y[top] = y;
    b->scissor_w[top] = width;
    b->scissor_h[top] = height;
    b->scissor_top++;
}

void bufferPopScissorRect(BufferPtr buffer) {
    Buffer *b = (Buffer*)buffer;
    if (b && b->scissor_top > 0) b->scissor_top--;
}

void bufferClearScissorRects(BufferPtr buffer) {
    Buffer *b = (Buffer*)buffer;
    if (b) b->scissor_top = 0;
}

// ── Kitty keyboard ─────────────────────────────────────────────────────

void enableKittyKeyboard(RendererPtr renderer, uint8_t flags) {
    (void)renderer; (void)flags;
}

void disableKittyKeyboard(RendererPtr renderer) {
    (void)renderer;
}

// ── Bracketed paste ────────────────────────────────────────────────────

void setBracketedPaste(RendererPtr renderer, bool enable) {
    (void)renderer;
    fprintf(stdout, enable ? "\033[?2004h" : "\033[?2004l");
    fflush(stdout);
}

// ── Terminal capabilities ──────────────────────────────────────────────

void getTerminalCapabilities(RendererPtr renderer) {
    (void)renderer;
}

void processCapabilityResponse(RendererPtr renderer, const uint8_t* data, size_t len) {
    (void)renderer; (void)data; (void)len;
}

// ── Terminal setup ─────────────────────────────────────────────────────

void setupTerminal(RendererPtr renderer, bool useAlternateScreen) {
    (void)renderer;
    if (useAlternateScreen) {
        // Enter alternate screen buffer and hide cursor
        fprintf(stdout, "\033[?1049h\033[?25l\033[2J\033[H");
    } else {
        // Just hide cursor and clear screen, no alternate screen
        fprintf(stdout, "\033[?25l\033[2J\033[H");
    }
    fflush(stdout);
}

void setTerminalTitle(RendererPtr renderer, const uint8_t* title, size_t len) {
    (void)renderer;
    fprintf(stdout, "\033]0;%.*s\007", (int)len, (const char*)title);
    fflush(stdout);
}

void setDebugOverlay(RendererPtr renderer, bool enable) {
    (void)renderer; (void)enable;
}

// ── Text buffer (rich text) — minimal stubs ────────────────────────────

static uint32_t text_buffer_count = 0;
static uint32_t text_buffer_lengths[256] = {0};

uint32_t createTextBuffer(uint8_t widthMethod) {
    (void)widthMethod;
    uint32_t id = text_buffer_count++;
    if (id < 256) text_buffer_lengths[id] = 0;
    return id;
}

void destroyTextBuffer(uint32_t tb) {
    if (tb < 256) text_buffer_lengths[tb] = 0;
}

uint32_t textBufferGetLength(uint32_t tb) {
    if (tb < 256) return text_buffer_lengths[tb];
    return 0;
}

void textBufferReset(uint32_t tb) {
    if (tb < 256) text_buffer_lengths[tb] = 0;
}

uint32_t textBufferWriteChunk(uint32_t tb, const uint8_t* text, size_t len,
                          const float* fg, const float* bg, uint8_t attrs) {
    if (tb < 256) text_buffer_lengths[tb] += (uint32_t)len;
    (void)text; (void)fg; (void)bg; (void)attrs;
    return (uint32_t)len;
}

void textBufferSetWrapWidth(uint32_t tb, uint32_t width)   { (void)tb; (void)width; }
void textBufferSetWrapMode(uint32_t tb, uint8_t mode)      { (void)tb; (void)mode; }
void textBufferSetSelection(uint32_t tb, uint32_t start, uint32_t end,
                            const float* bg_color, const float* fg_color) {
    (void)tb; (void)start; (void)end; (void)bg_color; (void)fg_color;
}
void textBufferResetSelection(uint32_t tb)                  { (void)tb; }

void bufferDrawTextBuffer(BufferPtr buffer, uint32_t tb, int32_t x, int32_t y,
                          int32_t clip_x, int32_t clip_y, uint32_t clip_width, uint32_t clip_height) {
    (void)buffer; (void)tb; (void)x; (void)y;
    (void)clip_x; (void)clip_y; (void)clip_width; (void)clip_height;
}

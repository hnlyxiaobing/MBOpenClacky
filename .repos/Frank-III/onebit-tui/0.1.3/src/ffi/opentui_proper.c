// Proper C wrapper for OpenTUI based on the official header
// This provides a clean interface for MoonBit FFI

#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

// Import the official OpenTUI C API
// We'll link against libopentui.dylib which provides these symbols
typedef struct CliRenderer CliRenderer;
typedef struct OptimizedBuffer OptimizedBuffer;

// External functions from libopentui
extern CliRenderer* createRenderer(uint32_t width, uint32_t height);
extern void destroyRenderer(CliRenderer* renderer, bool useAlternateScreen, uint32_t splitHeight);
extern void setUseThread(CliRenderer* renderer, bool useThread);
extern void setBackgroundColor(CliRenderer* renderer, const float* color);
extern void render(CliRenderer* renderer, bool force);
extern OptimizedBuffer* getNextBuffer(CliRenderer* renderer);
extern OptimizedBuffer* getCurrentBuffer(CliRenderer* renderer);
extern void clearTerminal(CliRenderer* renderer);
extern void resizeRenderer(CliRenderer* renderer, uint32_t width, uint32_t height);

// Buffer functions
extern OptimizedBuffer* createOptimizedBuffer(uint32_t width, uint32_t height, bool respectAlpha, uint8_t widthMethod);
extern void destroyOptimizedBuffer(OptimizedBuffer* buffer);
extern uint32_t getBufferWidth(OptimizedBuffer* buffer);
extern uint32_t getBufferHeight(OptimizedBuffer* buffer);
extern void bufferClear(OptimizedBuffer* buffer, const float* bg);
extern void bufferDrawText(OptimizedBuffer* buffer, const uint8_t* text, size_t textLen, 
                           uint32_t x, uint32_t y, const float* fg, const float* bg, uint8_t attributes);
extern void bufferFillRect(OptimizedBuffer* buffer, uint32_t x, uint32_t y, 
                          uint32_t width, uint32_t height, const float* bg);

// Cursor functions
extern void setCursorPosition(CliRenderer* renderer, int32_t x, int32_t y, bool visible);
extern void setCursorStyle(CliRenderer* renderer, const uint8_t* style, size_t styleLen, bool blinking);
extern void setCursorColor(CliRenderer* renderer, const float* color);

// Mouse functions
extern void enableMouse(CliRenderer* renderer, bool enableMovement);
extern void disableMouse(CliRenderer* renderer);

// === MoonBit-friendly wrapper functions ===
// These convert MoonBit's double arrays to float arrays that OpenTUI expects

// Initialize the renderer
CliRenderer* mb_createRenderer(uint32_t width, uint32_t height) {
    // Debug output to understand what's happening
    fprintf(stderr, "mb_createRenderer: Creating renderer %ux%u\n", width, height);
    
    CliRenderer* renderer = createRenderer(width, height);
    
    if (renderer == NULL) {
        fprintf(stderr, "mb_createRenderer: Failed to create renderer\n");
    } else {
        fprintf(stderr, "mb_createRenderer: Successfully created renderer at %p\n", (void*)renderer);
    }
    
    return renderer;
}

// Destroy renderer
void mb_destroyRenderer(CliRenderer* renderer, bool useAlternateScreen, uint32_t splitHeight) {
    if (renderer != NULL) {
        destroyRenderer(renderer, useAlternateScreen, splitHeight);
    }
}

// Set background color (converts double[4] to float[4])
void mb_setBackgroundColor(CliRenderer* renderer, const double* color) {
    if (renderer != NULL && color != NULL) {
        float fcolor[4] = {
            (float)color[0], (float)color[1], 
            (float)color[2], (float)color[3]
        };
        setBackgroundColor(renderer, fcolor);
    }
}

// Clear terminal
void mb_clearTerminal(CliRenderer* renderer) {
    if (renderer != NULL) {
        clearTerminal(renderer);
    }
}

// Render
void mb_render(CliRenderer* renderer, bool force) {
    if (renderer != NULL) {
        render(renderer, force);
    }
}

// Get next buffer
OptimizedBuffer* mb_getNextBuffer(CliRenderer* renderer) {
    if (renderer == NULL) return NULL;
    return getNextBuffer(renderer);
}

// Get buffer dimensions
uint32_t mb_getBufferWidth(OptimizedBuffer* buffer) {
    if (buffer == NULL) return 0;
    return getBufferWidth(buffer);
}

uint32_t mb_getBufferHeight(OptimizedBuffer* buffer) {
    if (buffer == NULL) return 0;
    return getBufferHeight(buffer);
}

// Clear buffer (converts double[4] to float[4])
void mb_bufferClear(OptimizedBuffer* buffer, const double* bg) {
    if (buffer != NULL && bg != NULL) {
        float fbg[4] = {(float)bg[0], (float)bg[1], (float)bg[2], (float)bg[3]};
        bufferClear(buffer, fbg);
    }
}

// Draw text (converts double arrays to float arrays)
void mb_bufferDrawText(OptimizedBuffer* buffer, const uint8_t* text, size_t textLen,
                      uint32_t x, uint32_t y, 
                      const double* fg, const double* bg, uint8_t attributes) {
    if (buffer == NULL || text == NULL || fg == NULL) return;
    
    float ffg[4] = {(float)fg[0], (float)fg[1], (float)fg[2], (float)fg[3]};
    
    if (bg != NULL) {
        float fbg[4] = {(float)bg[0], (float)bg[1], (float)bg[2], (float)bg[3]};
        bufferDrawText(buffer, text, textLen, x, y, ffg, fbg, attributes);
    } else {
        bufferDrawText(buffer, text, textLen, x, y, ffg, NULL, attributes);
    }
}

// Fill rectangle (converts double[4] to float[4])
void mb_bufferFillRect(OptimizedBuffer* buffer, uint32_t x, uint32_t y,
                       uint32_t width, uint32_t height, const double* bg) {
    if (buffer != NULL && bg != NULL) {
        float fbg[4] = {(float)bg[0], (float)bg[1], (float)bg[2], (float)bg[3]};
        bufferFillRect(buffer, x, y, width, height, fbg);
    }
}

// Set cursor position
void mb_setCursorPosition(CliRenderer* renderer, int32_t x, int32_t y, bool visible) {
    if (renderer != NULL) {
        setCursorPosition(renderer, x, y, visible);
    }
}

// Enable mouse
void mb_enableMouse(CliRenderer* renderer, bool enableMovement) {
    if (renderer != NULL) {
        enableMouse(renderer, enableMovement);
    }
}

// Test function to verify library is loaded
int mb_test_library() {
    fprintf(stderr, "mb_test_library: Testing OpenTUI library availability\n");
    
    // Try to create a small test renderer
    CliRenderer* test = createRenderer(10, 10);
    if (test != NULL) {
        fprintf(stderr, "mb_test_library: SUCCESS - Library is working\n");
        destroyRenderer(test, false, 0);
        return 1; // Success
    } else {
        fprintf(stderr, "mb_test_library: FAILED - Cannot create renderer\n");
        return 0; // Failure
    }
}

// --- Scissor / clip no-op stubs (until upstream provides real API) ---
void bufferPushScissorRect(OptimizedBuffer* buffer, int32_t x, int32_t y, uint32_t width, uint32_t height) {
    (void)buffer; (void)x; (void)y; (void)width; (void)height;
}

void bufferPopScissorRect(OptimizedBuffer* buffer) {
    (void)buffer;
}

void bufferClearScissorRects(OptimizedBuffer* buffer) {
    (void)buffer;
}

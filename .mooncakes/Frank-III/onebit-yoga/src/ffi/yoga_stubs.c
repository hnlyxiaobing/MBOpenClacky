// Yoga layout engine stub implementations for Windows
// These provide a minimal handle-based interface matching yoga_wrap.c's API.
// Layout calculations return default values - sufficient for non-interactive CLI mode.

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

// Simple handle table
#define MAX_HANDLES 4096
static void* node_table[MAX_HANDLES] = {0};
static void* config_table[MAX_HANDLES] = {0};
static int node_count = 0;
static int config_count = 0;

// Dummy node/config struct (just holds style values for basic layout)
typedef struct {
    float width, height;
    float left, top;
    int child_count;
} StubNode;

typedef struct {
    int web_defaults;
} StubConfig;

static int alloc_node(void) {
    if (node_count >= MAX_HANDLES) return -1;
    StubNode* n = (StubNode*)calloc(1, sizeof(StubNode));
    int h = node_count++;
    node_table[h] = n;
    return h;
}

static int alloc_config(void) {
    if (config_count >= MAX_HANDLES) return -1;
    StubConfig* c = (StubConfig*)calloc(1, sizeof(StubConfig));
    int h = config_count++;
    config_table[h] = c;
    return h;
}

// Config functions
int YGConfigNew_wrap(void) { return alloc_config(); }
void YGConfigFree_wrap(int h) { if (h >= 0 && h < config_count && config_table[h]) { free(config_table[h]); config_table[h] = NULL; } }
void YGConfigSetUseWebDefaults_wrap(int h, int e) { (void)h; (void)e; }

// Node lifecycle
int YGNodeNew_wrap(void) { return alloc_node(); }
int YGNodeNewWithConfig_wrap(int ch) { (void)ch; return alloc_node(); }
void YGNodeFree_wrap(int h) { if (h >= 0 && h < node_count && node_table[h]) { free(node_table[h]); node_table[h] = NULL; } }
void YGNodeFreeRecursive_wrap(int h) { YGNodeFree_wrap(h); }

// Layout calculation (no-op for stubs)
void YGNodeCalculateLayout_wrap(int h, float w, float hh, int dir) {
    (void)dir;
    if (h >= 0 && h < node_count && node_table[h]) {
        StubNode* n = (StubNode*)node_table[h];
        n->width = w > 0 ? w : 80.0f;
        n->height = hh > 0 ? hh : 24.0f;
    }
}

// Layout getters
float YGNodeLayoutGetLeft_wrap(int h) { return (h >= 0 && h < node_count && node_table[h]) ? ((StubNode*)node_table[h])->left : 0.0f; }
float YGNodeLayoutGetTop_wrap(int h) { return (h >= 0 && h < node_count && node_table[h]) ? ((StubNode*)node_table[h])->top : 0.0f; }
float YGNodeLayoutGetWidth_wrap(int h) { return (h >= 0 && h < node_count && node_table[h]) ? ((StubNode*)node_table[h])->width : 0.0f; }
float YGNodeLayoutGetHeight_wrap(int h) { return (h >= 0 && h < node_count && node_table[h]) ? ((StubNode*)node_table[h])->height : 0.0f; }

// Style setters (all no-ops for stubs - layout won't be accurate but won't crash)
void YGNodeStyleSetDisplay_wrap(int h, int d) { (void)h; (void)d; }
void YGNodeStyleSetFlexDirection_wrap(int h, int d) { (void)h; (void)d; }
void YGNodeStyleSetFlexWrap_wrap(int h, int w) { (void)h; (void)w; }
void YGNodeStyleSetFlex_wrap(int h, float f) { (void)h; (void)f; }
void YGNodeStyleSetFlexGrow_wrap(int h, float g) { (void)h; (void)g; }
void YGNodeStyleSetFlexShrink_wrap(int h, float s) { (void)h; (void)s; }
void YGNodeStyleSetFlexBasis_wrap(int h, float b) { (void)h; (void)b; }
void YGNodeStyleSetFlexBasisPercent_wrap(int h, float b) { (void)h; (void)b; }
void YGNodeStyleSetJustifyContent_wrap(int h, int j) { (void)h; (void)j; }
void YGNodeStyleSetAlignContent_wrap(int h, int a) { (void)h; (void)a; }
void YGNodeStyleSetAlignItems_wrap(int h, int a) { (void)h; (void)a; }
void YGNodeStyleSetAlignSelf_wrap(int h, int a) { (void)h; (void)a; }
void YGNodeStyleSetPositionType_wrap(int h, int p) { (void)h; (void)p; }
void YGNodeStyleSetPosition_wrap(int h, int e, float p) { (void)h; (void)e; (void)p; }
void YGNodeStyleSetPositionPercent_wrap(int h, int e, float p) { (void)h; (void)e; (void)p; }
void YGNodeStyleSetWidth_wrap(int h, float w) { if (h >= 0 && h < node_count && node_table[h]) ((StubNode*)node_table[h])->width = w; }
void YGNodeStyleSetWidthPercent_wrap(int h, float w) { (void)h; (void)w; }
void YGNodeStyleSetWidthAuto_wrap(int h) { (void)h; }
void YGNodeStyleSetHeight_wrap(int h, float hh) { if (h >= 0 && h < node_count && node_table[h]) ((StubNode*)node_table[h])->height = hh; }
void YGNodeStyleSetHeightPercent_wrap(int h, float hh) { (void)h; (void)hh; }
void YGNodeStyleSetHeightAuto_wrap(int h) { (void)h; }
void YGNodeStyleSetMinWidth_wrap(int h, float w) { (void)h; (void)w; }
void YGNodeStyleSetMinWidthPercent_wrap(int h, float w) { (void)h; (void)w; }
void YGNodeStyleSetMinHeight_wrap(int h, float hh) { (void)h; (void)hh; }
void YGNodeStyleSetMinHeightPercent_wrap(int h, float hh) { (void)h; (void)hh; }
void YGNodeStyleSetMaxWidth_wrap(int h, float w) { (void)h; (void)w; }
void YGNodeStyleSetMaxWidthPercent_wrap(int h, float w) { (void)h; (void)w; }
void YGNodeStyleSetMaxHeight_wrap(int h, float hh) { (void)h; (void)hh; }
void YGNodeStyleSetMaxHeightPercent_wrap(int h, float hh) { (void)h; (void)hh; }
void YGNodeStyleSetMargin_wrap(int h, int e, float m) { (void)h; (void)e; (void)m; }
void YGNodeStyleSetMarginPercent_wrap(int h, int e, float m) { (void)h; (void)e; (void)m; }
void YGNodeStyleSetMarginAuto_wrap(int h, int e) { (void)h; (void)e; }
void YGNodeStyleSetPadding_wrap(int h, int e, float p) { (void)h; (void)e; (void)p; }
void YGNodeStyleSetPaddingPercent_wrap(int h, int e, float p) { (void)h; (void)e; (void)p; }
void YGNodeStyleSetBorder_wrap(int h, int e, float b) { (void)h; (void)e; (void)b; }
void YGNodeStyleSetGap_wrap(int h, int g, float gap) { (void)h; (void)g; (void)gap; }

// Tree management
void YGNodeInsertChild_wrap(int ph, int ch, int idx) {
    (void)idx;
    if (ph >= 0 && ph < node_count && node_table[ph]) {
        ((StubNode*)node_table[ph])->child_count++;
    }
    (void)ch;
}
void YGNodeRemoveChild_wrap(int ph, int ch) { (void)ph; (void)ch; }
int YGNodeGetChildCount_wrap(int h) { return (h >= 0 && h < node_count && node_table[h]) ? ((StubNode*)node_table[h])->child_count : 0; }
int YGNodeGetChild_wrap(int ph, int idx) { (void)ph; (void)idx; return -1; }

// Measure function
void YGNodeSetMeasureFuncFixed_wrap(int h, float w, float hh) {
    if (h >= 0 && h < node_count && node_table[h]) {
        ((StubNode*)node_table[h])->width = w;
        ((StubNode*)node_table[h])->height = hh;
    }
}
void YGNodeClearMeasureFunc_wrap(int h) { (void)h; }

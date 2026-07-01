// C wrapper that provides a handle-based interface for MoonBit FFI
// This converts between MoonBit int handles and Yoga pointers

#include <yoga/Yoga.h>
#include <stdlib.h>
#include <string.h>

#ifdef __cplusplus
extern "C" {
#endif

// Handle table implementation with free list for recycling
typedef struct {
    void** items;
    int* free_list;  // Stack of free handles
    int free_count;  // Number of free handles
    int capacity;
    int count;
    int high_water_mark;  // Track highest used index for compaction
} HandleTable;

static HandleTable node_table = {NULL, NULL, 0, 0, 0, 0};
static HandleTable config_table = {NULL, NULL, 0, 0, 0, 0};

static int handle_table_add(HandleTable* table, void* ptr) {
    if (!ptr) return -1;
    
    // First check if we have any recycled handles
    if (table->free_count > 0) {
        int handle = table->free_list[--table->free_count];
        table->items[handle] = ptr;
        return handle;
    }
    
    // Need to expand if at capacity
    if (table->count >= table->capacity) {
        int new_capacity = table->capacity == 0 ? 16 : table->capacity * 2;
        void** new_items = (void**)realloc(table->items, new_capacity * sizeof(void*));
        if (!new_items) return -1;
        
        int* new_free_list = (int*)realloc(table->free_list, new_capacity * sizeof(int));
        if (!new_free_list) {
            // Rollback items realloc on failure
            if (new_items != table->items) {
                free(new_items);
            }
            return -1;
        }
        
        // Clear new slots
        memset(new_items + table->capacity, 0, (new_capacity - table->capacity) * sizeof(void*));
        
        table->items = new_items;
        table->free_list = new_free_list;
        table->capacity = new_capacity;
    }
    
    int handle = table->count++;
    table->items[handle] = ptr;
    
    // Update high water mark
    if (handle > table->high_water_mark) {
        table->high_water_mark = handle;
    }
    
    return handle;
}

static void* handle_table_get(HandleTable* table, int handle) {
    if (!table || !table->items || handle < 0 || handle >= table->count) return NULL;
    return table->items[handle];
}

static void handle_table_remove(HandleTable* table, int handle) {
    if (!table || !table->items) return;
    if (handle >= 0 && handle < table->count && table->items[handle] != NULL) {
        table->items[handle] = NULL;
        
        // Add to free list for recycling
        if (table->free_list && table->free_count < table->capacity) {
            table->free_list[table->free_count++] = handle;
        }
        
        // Update high water mark if this was the highest handle
        if (handle == table->high_water_mark) {
            // Find new high water mark
            int new_mark = -1;
            for (int i = table->high_water_mark - 1; i >= 0; i--) {
                if (table->items[i] != NULL) {
                    new_mark = i;
                    break;
                }
            }
            table->high_water_mark = new_mark;
        }
    }
}

// Compact the handle table to reduce memory usage
static void handle_table_compact(HandleTable* table) {
    if (!table) return;
    
    if (table->high_water_mark < 0) {
        // Table is empty, reset everything
        if (table->items) {
            free(table->items);
            table->items = NULL;
        }
        if (table->free_list) {
            free(table->free_list);
            table->free_list = NULL;
        }
        table->capacity = 0;
        table->count = 0;
        table->free_count = 0;
        table->high_water_mark = -1;
        return;
    }
    
    // Only compact if we're using less than 25% of capacity
    int target_capacity = table->high_water_mark + 1;
    if (target_capacity < 16) target_capacity = 16;  // Minimum capacity
    
    if (target_capacity < table->capacity / 4) {
        void** new_items = (void**)realloc(table->items, target_capacity * sizeof(void*));
        if (new_items) {
            table->items = new_items;
        }
        
        int* new_free_list = (int*)realloc(table->free_list, target_capacity * sizeof(int));
        if (new_free_list) {
            table->free_list = new_free_list;
        }
        
        table->capacity = target_capacity;
        table->count = target_capacity;
        
        // Rebuild free list
        table->free_count = 0;
        for (int i = 0; i <= table->high_water_mark; i++) {
            if (table->items[i] == NULL && table->free_count < table->capacity) {
                table->free_list[table->free_count++] = i;
            }
        }
    }
}

// Config wrapper functions
int YGConfigNew_wrap() {
    YGConfigRef config = YGConfigNew();
    return handle_table_add(&config_table, config);
}

void YGConfigFree_wrap(int handle) {
    YGConfigRef config = (YGConfigRef)handle_table_get(&config_table, handle);
    if (config) {
        YGConfigFree(config);
        handle_table_remove(&config_table, handle);
        
        // Periodically compact the table
        if (config_table.free_count > 32 && config_table.free_count > config_table.capacity / 2) {
            handle_table_compact(&config_table);
        }
    }
}

void YGConfigSetUseWebDefaults_wrap(int handle, int enabled) {
    YGConfigRef config = (YGConfigRef)handle_table_get(&config_table, handle);
    if (config) {
        YGConfigSetUseWebDefaults(config, enabled != 0);
    }
}

// Node wrapper functions
int YGNodeNew_wrap() {
    YGNodeRef node = YGNodeNew();
    return handle_table_add(&node_table, node);
}

int YGNodeNewWithConfig_wrap(int config_handle) {
    YGConfigRef config = (YGConfigRef)handle_table_get(&config_table, config_handle);
    YGNodeRef node = config ? YGNodeNewWithConfig(config) : YGNodeNew();
    return handle_table_add(&node_table, node);
}

void YGNodeFree_wrap(int handle) {
    YGNodeRef node = (YGNodeRef)handle_table_get(&node_table, handle);
    if (node) {
        // Free any user context associated with this node
        void* ctx = YGNodeGetContext(node);
        if (ctx) {
            free(ctx);
            YGNodeSetContext(node, NULL);
        }
        YGNodeFree(node);
        handle_table_remove(&node_table, handle);
        
        // Periodically compact the table
        if (node_table.free_count > 32 && node_table.free_count > node_table.capacity / 2) {
            handle_table_compact(&node_table);
        }
    }
}

// Helper to recursively remove handles for a node and its children
static void remove_node_handles_recursive(YGNodeRef node) {
    if (!node) return;
    
    // First, recursively process all children
    int child_count = YGNodeGetChildCount(node);
    for (int i = 0; i < child_count; i++) {
        YGNodeRef child = YGNodeGetChild(node, i);
        if (child) {
            remove_node_handles_recursive(child);
        }
    }
    
    // Then remove this node's handle from the table
    for (int i = 0; i < node_table.count; i++) {
        if (node_table.items[i] == node) {
            node_table.items[i] = NULL;
            break;
        }
    }
}

static void free_node_contexts_recursive(YGNodeRef n) {
    if (!n) return;
    int child_count = YGNodeGetChildCount(n);
    for (int i = 0; i < child_count; i++) {
        YGNodeRef c = YGNodeGetChild(n, i);
        free_node_contexts_recursive(c);
    }
    void* cctx = YGNodeGetContext(n);
    if (cctx) {
        free(cctx);
        YGNodeSetContext(n, NULL);
    }
}

void YGNodeFreeRecursive_wrap(int handle) {
    YGNodeRef node = (YGNodeRef)handle_table_get(&node_table, handle);
    if (node) {
        // Recursively free user contexts to avoid leaks
        free_node_contexts_recursive(node);
        // First remove all handles for this node and its children
        remove_node_handles_recursive(node);
        // Then free the actual Yoga nodes
        YGNodeFreeRecursive(node);
    }
}

// Layout calculation
void YGNodeCalculateLayout_wrap(int handle, float width, float height, int direction) {
    YGNodeRef node = (YGNodeRef)handle_table_get(&node_table, handle);
    if (node) {
        YGNodeCalculateLayout(node, width, height, (YGDirection)direction);
    }
}

// Layout getters
float YGNodeLayoutGetLeft_wrap(int handle) {
    YGNodeRef node = (YGNodeRef)handle_table_get(&node_table, handle);
    return node ? YGNodeLayoutGetLeft(node) : 0.0f;
}

float YGNodeLayoutGetTop_wrap(int handle) {
    YGNodeRef node = (YGNodeRef)handle_table_get(&node_table, handle);
    return node ? YGNodeLayoutGetTop(node) : 0.0f;
}

float YGNodeLayoutGetWidth_wrap(int handle) {
    YGNodeRef node = (YGNodeRef)handle_table_get(&node_table, handle);
    return node ? YGNodeLayoutGetWidth(node) : 0.0f;
}

float YGNodeLayoutGetHeight_wrap(int handle) {
    YGNodeRef node = (YGNodeRef)handle_table_get(&node_table, handle);
    return node ? YGNodeLayoutGetHeight(node) : 0.0f;
}

// Style setters
void YGNodeStyleSetDisplay_wrap(int handle, int display) {
    YGNodeRef node = (YGNodeRef)handle_table_get(&node_table, handle);
    if (node) {
        YGNodeStyleSetDisplay(node, (YGDisplay)display);
    }
}

void YGNodeStyleSetFlexDirection_wrap(int handle, int direction) {
    YGNodeRef node = (YGNodeRef)handle_table_get(&node_table, handle);
    if (node) {
        YGNodeStyleSetFlexDirection(node, (YGFlexDirection)direction);
    }
}

void YGNodeStyleSetFlexWrap_wrap(int handle, int wrap) {
    YGNodeRef node = (YGNodeRef)handle_table_get(&node_table, handle);
    if (node) {
        YGNodeStyleSetFlexWrap(node, (YGWrap)wrap);
    }
}

void YGNodeStyleSetFlex_wrap(int handle, float flex) {
    YGNodeRef node = (YGNodeRef)handle_table_get(&node_table, handle);
    if (node) {
        YGNodeStyleSetFlex(node, flex);
    }
}

void YGNodeStyleSetFlexGrow_wrap(int handle, float grow) {
    YGNodeRef node = (YGNodeRef)handle_table_get(&node_table, handle);
    if (node) {
        YGNodeStyleSetFlexGrow(node, grow);
    }
}

void YGNodeStyleSetFlexShrink_wrap(int handle, float shrink) {
    YGNodeRef node = (YGNodeRef)handle_table_get(&node_table, handle);
    if (node) {
        YGNodeStyleSetFlexShrink(node, shrink);
    }
}

void YGNodeStyleSetFlexBasis_wrap(int handle, float basis) {
    YGNodeRef node = (YGNodeRef)handle_table_get(&node_table, handle);
    if (node) {
        YGNodeStyleSetFlexBasis(node, basis);
    }
}

void YGNodeStyleSetFlexBasisPercent_wrap(int handle, float basis) {
    YGNodeRef node = (YGNodeRef)handle_table_get(&node_table, handle);
    if (node) {
        YGNodeStyleSetFlexBasisPercent(node, basis);
    }
}

// Justify & Align
void YGNodeStyleSetJustifyContent_wrap(int handle, int justify) {
    YGNodeRef node = (YGNodeRef)handle_table_get(&node_table, handle);
    if (node) {
        YGNodeStyleSetJustifyContent(node, (YGJustify)justify);
    }
}

void YGNodeStyleSetAlignContent_wrap(int handle, int align) {
    YGNodeRef node = (YGNodeRef)handle_table_get(&node_table, handle);
    if (node) {
        YGNodeStyleSetAlignContent(node, (YGAlign)align);
    }
}

void YGNodeStyleSetAlignItems_wrap(int handle, int align) {
    YGNodeRef node = (YGNodeRef)handle_table_get(&node_table, handle);
    if (node) {
        YGNodeStyleSetAlignItems(node, (YGAlign)align);
    }
}

void YGNodeStyleSetAlignSelf_wrap(int handle, int align) {
    YGNodeRef node = (YGNodeRef)handle_table_get(&node_table, handle);
    if (node) {
        YGNodeStyleSetAlignSelf(node, (YGAlign)align);
    }
}

// Position
void YGNodeStyleSetPositionType_wrap(int handle, int position) {
    YGNodeRef node = (YGNodeRef)handle_table_get(&node_table, handle);
    if (node) {
        YGNodeStyleSetPositionType(node, (YGPositionType)position);
    }
}

void YGNodeStyleSetPosition_wrap(int handle, int edge, float position) {
    YGNodeRef node = (YGNodeRef)handle_table_get(&node_table, handle);
    if (node) {
        YGNodeStyleSetPosition(node, (YGEdge)edge, position);
    }
}

void YGNodeStyleSetPositionPercent_wrap(int handle, int edge, float position) {
    YGNodeRef node = (YGNodeRef)handle_table_get(&node_table, handle);
    if (node) {
        YGNodeStyleSetPositionPercent(node, (YGEdge)edge, position);
    }
}

// Size
void YGNodeStyleSetWidth_wrap(int handle, float width) {
    YGNodeRef node = (YGNodeRef)handle_table_get(&node_table, handle);
    if (node) {
        YGNodeStyleSetWidth(node, width);
    }
}

void YGNodeStyleSetWidthPercent_wrap(int handle, float width) {
    YGNodeRef node = (YGNodeRef)handle_table_get(&node_table, handle);
    if (node) {
        YGNodeStyleSetWidthPercent(node, width);
    }
}

void YGNodeStyleSetWidthAuto_wrap(int handle) {
    YGNodeRef node = (YGNodeRef)handle_table_get(&node_table, handle);
    if (node) {
        YGNodeStyleSetWidthAuto(node);
    }
}

void YGNodeStyleSetHeight_wrap(int handle, float height) {
    YGNodeRef node = (YGNodeRef)handle_table_get(&node_table, handle);
    if (node) {
        YGNodeStyleSetHeight(node, height);
    }
}

void YGNodeStyleSetHeightPercent_wrap(int handle, float height) {
    YGNodeRef node = (YGNodeRef)handle_table_get(&node_table, handle);
    if (node) {
        YGNodeStyleSetHeightPercent(node, height);
    }
}

void YGNodeStyleSetHeightAuto_wrap(int handle) {
    YGNodeRef node = (YGNodeRef)handle_table_get(&node_table, handle);
    if (node) {
        YGNodeStyleSetHeightAuto(node);
    }
}

// Min/Max Size
void YGNodeStyleSetMinWidth_wrap(int handle, float width) {
    YGNodeRef node = (YGNodeRef)handle_table_get(&node_table, handle);
    if (node) {
        YGNodeStyleSetMinWidth(node, width);
    }
}

void YGNodeStyleSetMinWidthPercent_wrap(int handle, float width) {
    YGNodeRef node = (YGNodeRef)handle_table_get(&node_table, handle);
    if (node) {
        YGNodeStyleSetMinWidthPercent(node, width);
    }
}

void YGNodeStyleSetMinHeight_wrap(int handle, float height) {
    YGNodeRef node = (YGNodeRef)handle_table_get(&node_table, handle);
    if (node) {
        YGNodeStyleSetMinHeight(node, height);
    }
}

void YGNodeStyleSetMinHeightPercent_wrap(int handle, float height) {
    YGNodeRef node = (YGNodeRef)handle_table_get(&node_table, handle);
    if (node) {
        YGNodeStyleSetMinHeightPercent(node, height);
    }
}

void YGNodeStyleSetMaxWidth_wrap(int handle, float width) {
    YGNodeRef node = (YGNodeRef)handle_table_get(&node_table, handle);
    if (node) {
        YGNodeStyleSetMaxWidth(node, width);
    }
}

void YGNodeStyleSetMaxWidthPercent_wrap(int handle, float width) {
    YGNodeRef node = (YGNodeRef)handle_table_get(&node_table, handle);
    if (node) {
        YGNodeStyleSetMaxWidthPercent(node, width);
    }
}

void YGNodeStyleSetMaxHeight_wrap(int handle, float height) {
    YGNodeRef node = (YGNodeRef)handle_table_get(&node_table, handle);
    if (node) {
        YGNodeStyleSetMaxHeight(node, height);
    }
}

void YGNodeStyleSetMaxHeightPercent_wrap(int handle, float height) {
    YGNodeRef node = (YGNodeRef)handle_table_get(&node_table, handle);
    if (node) {
        YGNodeStyleSetMaxHeightPercent(node, height);
    }
}

// Margin
void YGNodeStyleSetMargin_wrap(int handle, int edge, float margin) {
    YGNodeRef node = (YGNodeRef)handle_table_get(&node_table, handle);
    if (node) {
        YGNodeStyleSetMargin(node, (YGEdge)edge, margin);
    }
}

void YGNodeStyleSetMarginPercent_wrap(int handle, int edge, float margin) {
    YGNodeRef node = (YGNodeRef)handle_table_get(&node_table, handle);
    if (node) {
        YGNodeStyleSetMarginPercent(node, (YGEdge)edge, margin);
    }
}

void YGNodeStyleSetMarginAuto_wrap(int handle, int edge) {
    YGNodeRef node = (YGNodeRef)handle_table_get(&node_table, handle);
    if (node) {
        YGNodeStyleSetMarginAuto(node, (YGEdge)edge);
    }
}

// Padding
void YGNodeStyleSetPadding_wrap(int handle, int edge, float padding) {
    YGNodeRef node = (YGNodeRef)handle_table_get(&node_table, handle);
    if (node) {
        YGNodeStyleSetPadding(node, (YGEdge)edge, padding);
    }
}

void YGNodeStyleSetPaddingPercent_wrap(int handle, int edge, float padding) {
    YGNodeRef node = (YGNodeRef)handle_table_get(&node_table, handle);
    if (node) {
        YGNodeStyleSetPaddingPercent(node, (YGEdge)edge, padding);
    }
}

// Border
void YGNodeStyleSetBorder_wrap(int handle, int edge, float border) {
    YGNodeRef node = (YGNodeRef)handle_table_get(&node_table, handle);
    if (node) {
        YGNodeStyleSetBorder(node, (YGEdge)edge, border);
    }
}

// Gap
void YGNodeStyleSetGap_wrap(int handle, int gutter, float gap) {
    YGNodeRef node = (YGNodeRef)handle_table_get(&node_table, handle);
    if (node) {
        YGNodeStyleSetGap(node, (YGGutter)gutter, gap);
    }
}

// Tree management
void YGNodeInsertChild_wrap(int parent_handle, int child_handle, int index) {
    YGNodeRef parent = (YGNodeRef)handle_table_get(&node_table, parent_handle);
    YGNodeRef child = (YGNodeRef)handle_table_get(&node_table, child_handle);
    if (parent && child) {
        YGNodeInsertChild(parent, child, index);
    }
}

void YGNodeRemoveChild_wrap(int parent_handle, int child_handle) {
    YGNodeRef parent = (YGNodeRef)handle_table_get(&node_table, parent_handle);
    YGNodeRef child = (YGNodeRef)handle_table_get(&node_table, child_handle);
    if (parent && child) {
        YGNodeRemoveChild(parent, child);
        // Note: We don't remove the child's handle here because it might be
        // referenced elsewhere. The handle will be removed when YGNodeFree is called.
    }
}

int YGNodeGetChildCount_wrap(int handle) {
    YGNodeRef parent = (YGNodeRef)handle_table_get(&node_table, handle);
    return parent ? YGNodeGetChildCount(parent) : 0;
}

int YGNodeGetChild_wrap(int parent_handle, int index) {
    YGNodeRef parent = (YGNodeRef)handle_table_get(&node_table, parent_handle);
    if (!parent) return -1;
    
    YGNodeRef child = YGNodeGetChild(parent, index);
    if (!child) return -1;
    
    // Check if child already has a handle
    for (int i = 0; i < node_table.count; i++) {
        if (node_table.items[i] == child) {
            return i;
        }
    }
    
    // Add new handle for child
    return handle_table_add(&node_table, child);
}

// ---------------- Measure function (fixed) ----------------
// We provide a simple fixed-size measure callback using node context.

typedef struct {
    float width;
    float height;
} MBMeasureFixed;

static YGSize mb_measure_fixed(
    YGNodeConstRef node,
    float width,
    YGMeasureMode widthMode,
    float height,
    YGMeasureMode heightMode
) {
    (void)width; (void)widthMode; (void)height; (void)heightMode;
    MBMeasureFixed* ctx = (MBMeasureFixed*)YGNodeGetContext((YGNodeRef)node);
    YGSize size;
    if (!ctx) {
        size.width = 0.0f;
        size.height = 0.0f;
        return size;
    }
    size.width = ctx->width;
    size.height = ctx->height;
    return size;
}

// Set a fixed measure function on a node and store width/height in context.
void YGNodeSetMeasureFuncFixed_wrap(int handle, float width, float height) {
    YGNodeRef node = (YGNodeRef)handle_table_get(&node_table, handle);
    if (!node) return;
    MBMeasureFixed* ctx = (MBMeasureFixed*)YGNodeGetContext(node);
    if (!ctx) {
        ctx = (MBMeasureFixed*)malloc(sizeof(MBMeasureFixed));
        if (!ctx) return;
        YGNodeSetContext(node, ctx);
    }
    ctx->width = width;
    ctx->height = height;
    YGNodeSetMeasureFunc(node, mb_measure_fixed);
}

// Clear any measure function and free context if we own it.
void YGNodeClearMeasureFunc_wrap(int handle) {
    YGNodeRef node = (YGNodeRef)handle_table_get(&node_table, handle);
    if (!node) return;
    YGNodeSetMeasureFunc(node, NULL);
    void* ctx = YGNodeGetContext(node);
    if (ctx) {
        free(ctx);
        YGNodeSetContext(node, NULL);
    }
}
#ifdef __cplusplus
}
#endif

# TUI 重构：基于 mizchi/tui 的分层迁移

## 为什么干
lib/tui/ 有 12,351 行手写渲染代码。无 VDOM/diff（200ms 全量重绘）、手写布局（只有 Column/Row/Border）、ANSI 耦合（16色）。用 mizchi/tui 替换渲染层，保留业务逻辑。

## 成功标准
重绘 O(changed) 替代 O(screen)；首字延迟 <30ms（现 ~100ms）；窗口缩放自动重排；Unicode 圆角边框；truecolor；CJK 不错位；Markdown 表格可渲染；鼠标点击/滚动/选区可用。

## 必达验收（5条）
1. 所有 wbtest 通过（≥12个）
2. `--tui-eval` 场景全部通过
3. 性能 ≥ 当前 2 倍
4. CJK 不错位
5. CLI 行为完全保留

## 我替领导拍的板

**主框架**：`mizchi/tui` v0.10.0（MIT，141 commits，VDOM+Flexbox+20+组件）

**配套库**：`crater`（Flexbox/Grid）、`signals`（响应式状态）、`displaytext` v0.1.5（CJK）、`style_print` v0.1.7（truecolor SGR）、`tabular` v0.5.2（表格）、`colors` v0.8.1（颜色空间）、`terminal_size` v0.1.5

**四层架构**：
- Layer 4：Agent 应用层（保留 tui_controller + Agent UX）
- Layer 3：自研组件层（markdown/diff/thinking_live/clipboard/streaming/keymap/brand）
- Layer 2：mizchi/tui 渲染层（零修改 import）
- Layer 1：基础层（tty/displaytext/colors/style_print/tabular）

## 实施路线

**阶段 1（1-2周）基础渲染替换**：删除 node.mbt/screen_buffer.mbt/layout_manager.mbt/cjk_width.mbt → 用 @tui.vnode + @tui.render + @displaytext 替换。创建 ui/vnode_builder.mbt。验收：wbtest 全过，行为不变。

**阶段 2（2-3周）状态与主题**：state.mbt → @signals.Signal；theme.mbt → style_print（truecolor）；markdown 表格 → @tabular。验收：truecolor 可见，CJK 不错位。

**阶段 3（3-5周）交互增强**：鼠标端到端（SGR→@tui.events→controller）；Tab 焦点；视口虚拟化（1000+行流畅）；OSC 52 选区复制；升级 dialog/slash_commands/thinking_view/todo_area/progress_stack。

**阶段 4（5-6周）打磨**：thinking live 动画；diff 渲染器（unified/side-by-side）；工具输出折叠；品牌定制（3套模板）；性能调优+降级。

## 文件迁移
删除：node.mbt(219行)、screen_buffer.mbt(120)、layout_manager.mbt(241)、cjk_width.mbt(~80)
改写：state.mbt(380→Signal)、theme.mbt(~100→style_print)、markdown.mbt(411→@tabular)
保留适配：tui_controller.mbt(1569) + 其他 18 文件(~6500行，接口微调)

## 风险
mizchi/tui 停更(低/高→LunarTUI backup)；缺能力(中/中→自研补200-500行)；signal冲突(中/中→controller保持同步)；wbtest改写(中/中→断言不变只改setup)；CJK错位(中/中→displaytext+fallback)。每阶段独立PR可revert。

## 禁区
1. 不许破坏 agent 行为（lib/agent/* 接口不变）
2. 不许引入新 C FFI（全是纯 MoonBit）
3. 不许删除现有测试（断言不变只改 setup）
4. 不许跳过验收（每阶段通过对应验收点）
5. 不许静默失败（渲染错误降级到纯文本）

## 开工检查
1. `moon build --target native --release cmd` 成功
2. `moon test` 通过（≥12 wbtest）
3. `--tui-eval test/scenarios/tui/` 跑通
4. mizchi/tui v0.10.0 在 mooncakes 可用

## 完成条件
1. 硬：wbtest 全过 + tui-eval 100% + 性能≥2倍
2. 硬：CJK不错位 + truecolor + 鼠标可用
3. 软：视觉接近 Claude Code 水平

# skill — SKILL.md 解析 · 技能注册 · GEP 进化引擎

> 路径: `lib/skill/` · 12 mbt（9 源 + 3 测试）· 技能管理与进化

## 入口函数

| 函数 | 文件 | 说明 |
|------|------|------|
| `discover_skills(env)` | `skill.mbt` | 从 discovery_paths 扫描并加载所有 SKILL.md |
| `load_skill_from_content(name, content, dir?)` | `skill.mbt` | 解析单个 SKILL.md 文件（frontmatter + body） |
| `register_default_skills(registry)` | `default_skills.mbt` | 注册 17 个内置默认技能 |
| `EvolutionEngine::evolve(scenario)` | `evolution.mbt` | 触发技能进化流程 |
| `parse_frontmatter(content)` | `skill.mbt` | 解析 YAML frontmatter 元数据 |

## 关键类型

### 核心 Struct
- **`Skill`** — 技能定义（name, description, user_invocable, allowed_tools, context, agent_type, hooks, fork_agent, model, source...）
- **`SkillRegistry`** — 技能注册表（skills: Map[String, Skill]，discovery_paths）
- **`SkillResult`** — 执行结果（success, output, skill_name）
- **`DefaultSkillMeta`** — 默认技能元信息（name, description, user_invocable, allowed_tools, category）

### 进化引擎
- **`EvolutionEngine`** — 进化引擎（持有 SkillReflector + AutoCreator）
- **`EvolutionScenario`** — 进化场景：`PostExecution(skill_name, result, iterations) | AutoDetect(conversation_history, iteration_count)`
- **`EvolutionResult`** — 进化结果（action: EvolutionAction, skill_name, diff_summary）
- **`EvolutionAction`** — `Created | Improved | NoChange`
- **`SkillReflector`** — 技能反思器（reflect → ReflectionReport）
- **`ReflectionReport`** — 反思报告（performance_score, suggestions, should_improve）
- **`AutoCreator`** — 自动创建器（detect_candidates → CreationCandidate）
- **`CreationCandidate`** — 创建候选（name, description, pattern_count, confidence）

## 核心调用链

```
Agent::load_skills(env)
  └─ discover_skills(env)
      ├─ default_discovery_paths(working_dir)  # 确定扫描路径
      └─ load_skill_from_content(name, content) # 解析 SKILL.md
          ├─ parse_frontmatter(content)         # 提取 YAML 元数据
          └─ 构建 Skill 对象
  └─ SkillRegistry::register(skill)

# 技能进化流程
EvolutionEngine::evolve(scenario)
  ├─ SkillReflector::reflect(skill_name, result, iterations)
  │   └─ 评估 performance_score → ReflectionReport
  └─ if should_improve:
      └─ SkillReflector::apply_improvements(report) → 修改 SKILL.md
```

## 文件职责分组

| 文件 | 职责 |
|------|------|
| `skill.mbt` | Skill 类型、SKILL.md 解析、load_skill_from_content |
| `registry.mbt` | SkillRegistry、技能注册/查询/列表/删除 |
| `default_skills.mbt` | DefaultSkillMeta、get_default_skill_metas（17 个）、register_default_skills |
| `discovery.mbt` | default_discovery_paths、discover_skills（支持 SKILL.md 和 skill.json） |
| `loader.mbt` | parse_frontmatter（YAML frontmatter 解析）、load_skill_from_json_value |
| `executor.mbt` | SkillResult、build_skill_context（技能执行上下文注入） |
| `evolution.mbt` | EvolutionEngine、技能进化流程 |
| `reflector.mbt` | SkillReflector、技能反思与改进 |
| `auto_creator.mbt` | AutoCreator、自动技能创建 |
## 外部依赖

- `assets/skills/` — 默认技能 SKILL.md 文件目录
- `~/.mbopenclacky/skills/` — 用户技能目录（可编辑、可删除）
- `moonbitlang/core/json` — JSON 序列化
- `lib/web/handlers_skills.mbt` — Web REST API 层（CRUD、install、content get/put、toggle、store、creator）

## 默认技能清单（17 个代码注册 + 1 个仅资源，共 18 个目录）

`assets/skills/` 目录下共有 18 个技能目录，其中 17 个在代码中注册：

代码注册（`default_skills.mbt`）: `code-explorer`, `mcp-manager`, `media-gen`, `persist-memory`, `recall-memory`, `search-skills`, `skill-creator`, `cron-task-creator`, `deploy`, `onboard`, `product-help`, `browser_setup`, `channel_manager`, `new`, `personal_website`, `skill_add`, `meeting-summarizer`。

仅资源目录（未在代码中注册）: `extend-openclacky`。

## 风险点

1. **Frontmatter 解析** — `parse_frontmatter()` 自实现 YAML 解析，不支持复杂 YAML 语法
2. **进化引擎依赖 LLM** — `SkillReflector::reflect()` 和 `apply_improvements()` 需要 LLM 调用，失败时技能不会进化
3. **技能路径硬编码** — `default_discovery_paths()` 依赖 `assets/skills/` 路径
4. **技能名冲突** — 用户自定义技能可能与默认技能同名覆盖
5. **技能安装安全** — `handle_skills_install` 从 builtin 目录复制 SKILL.md，需确保路径遍历已被 `is_valid_skill_name()` 阻止

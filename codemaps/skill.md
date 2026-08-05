# skill — SKILL.md 解析 · 技能注册 · GEP 进化引擎

> 路径: `lib/skill/` · 13 mbt（9 源 + 4 测试）· 技能管理与进化

## 入口函数

| 函数 | 文件 | 说明 |
|------|------|------|
| `discover_skills(file_contents)` | `discovery.mbt` | 从路径→内容 map 解析并加载所有 SKILL.md |
| `read_skill_files(paths)` | `discovery.mbt` | 递归扫描发现目录（深度 ≤3），收集 SKILL.md/skill.json 为 map |
| `default_discovery_paths(working_dir)` | `discovery.mbt` | 5 条发现路径（低→高优先级，同名后者覆盖前者） |
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
Agent::discover_workspace_skills()          # CLI/Web/onboard 启动时调用
  └─ @skill.read_skill_files(@skill.default_discovery_paths(working_dir))
      # 发现顺序：~/.mbopenclacky/skills → <dir>/.qoder/skills
      #         → <dir>/skills → <dir>/.skills → <dir>/.clacky/skills
  └─ Agent::load_skills(file_contents)
      └─ discover_skills(file_contents)
          └─ load_skill_from_content(content, path, dir?)  # 解析 SKILL.md
              ├─ parse_frontmatter(content)         # 提取 YAML 元数据
              └─ 构建 Skill 对象
      └─ SkillRegistry::register(skill)   # 同名后注册覆盖先注册

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
| `discovery.mbt` | default_discovery_paths（5 条路径）、read_skill_files（递归扫描）、discover_skills（支持 SKILL.md 和 skill.json） |
| `loader.mbt` | parse_frontmatter（YAML frontmatter 解析）、load_skill_from_json_value |
| `executor.mbt` | SkillResult、build_skill_context（技能执行上下文注入） |
| `evolution.mbt` | EvolutionEngine、技能进化流程 |
| `reflector.mbt` | SkillReflector、技能反思与改进 |
| `auto_creator.mbt` | AutoCreator、自动技能创建 |
## 外部依赖

- `assets/skills/` — 默认技能 SKILL.md 文件目录
- 技能发现目录（按优先级从低到高）：`~/.mbopenclacky/skills/`（用户全局，可编辑、可删除）、`<working_dir>/.qoder/skills/`、`<working_dir>/skills/`、`<working_dir>/.skills/`、`<working_dir>/.clacky/skills/`（项目级，最高优先级）
- `moonbitlang/core/json` — JSON 序列化
- `lib/web/handlers_skills.mbt` — Web REST API 层（CRUD、install、content get/put、toggle、store、creator）

## 默认技能清单（17 个代码注册 + 1 个仅资源，共 18 个目录）

`assets/skills/` 目录下共有 18 个技能目录，其中 17 个在代码中注册：

代码注册（`default_skills.mbt`）: `code-explorer`, `mcp-manager`, `media-gen`, `persist-memory`, `recall-memory`, `search-skills`, `skill-creator`, `cron-task-creator`, `deploy`, `onboard`, `product-help`, `browser_setup`, `channel_manager`, `new`, `personal_website`, `skill_add`, `meeting-summarizer`。

仅资源目录（未在代码中注册）: `extend-openclacky`。

## 风险点

1. **Frontmatter 解析** — `parse_frontmatter()` 自实现 YAML 解析，不支持复杂 YAML 语法
2. **进化引擎依赖 LLM** — `SkillReflector::reflect()` 和 `apply_improvements()` 需要 LLM 调用，失败时技能不会进化
3. **发现路径优先级** — `default_discovery_paths()` 按低→高顺序注册，同名技能后注册覆盖先注册；新增发现目录时需同步更新 `skill_wbtest.mbt` 断言
4. **技能名冲突** — 用户自定义技能可能与默认技能同名覆盖
5. **技能安装安全** — `handle_skills_install` 从 builtin 目录复制 SKILL.md，需确保路径遍历已被 `is_valid_skill_name()` 阻止

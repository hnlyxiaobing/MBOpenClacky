/// # diff-harness 回归测试：config_cli 模块（config-001 ~ config-020）
///
/// 迁移自 diff-harness（D:/MoonBit/diff-harness）`cases/config_cli/test_cases.json`。
/// 期望值已冻结为本文件中的字面量：
/// - ruby_output 为 Ruby openclacky 实测驱动记录（可信），按"以 Ruby 为准"冻结；
///   其中 current_model_id 为随机 UUID，只断言非空/存在性，不断言具体值。
/// - moonbit_output 为 Python 模拟（不可信），凡与代码实测冲突处一律以代码实测为准，
///   并在注释中说明。
/// - wontfix 条目（BUG-0016/0017/0018/0019/0021，MB 扩展或等价表示）直接冻结
///   MB 当前行为为期望。
///
/// 环境变量注入方案：`moonbitlang/core/env` 提供 set_env_var/unset_env_var，
/// 测试内先保存并清空四个前缀（CLACKY/OPENCLACKY/CLAUDE/MBOPENCLACKY）的全部
/// 相关变量，注入用例所需值，结束后恢复。限制：若断言中途失败，恢复步骤会被跳过，
/// 但每个用例开头都会重新清空，污染不会跨用例扩散。
///
/// BUG 台账：diff-harness/reports/BUGS.md；证据：cases/config_cli/test_cases.json。

///|
/// 四个前缀 × 相关后缀的全量环境变量清单（用于保存/清空/恢复）。
fn config_env_keys() -> Array[String] {
  let keys : Array[String] = []
  for prefix in ["CLACKY", "OPENCLACKY", "CLAUDE", "MBOPENCLACKY"] {
    for
      suffix in [
        "API_KEY", "BASE_URL", "MODEL", "PROVIDER", "PROXY_URL", "FALLBACK_MODEL",
        "MAX_TOKENS", "COMPRESSION_THRESHOLD", "ANTHROPIC_FORMAT", "VERBOSE",
      ] {
      keys.push(prefix + "_" + suffix)
    }
  }
  keys
}

///|
/// 保存当前值并清空全部相关环境变量，返回快照供恢复。
fn clear_and_save_env() -> Array[(String, String?)] {
  let saved : Array[(String, String?)] = []
  for k in config_env_keys() {
    saved.push((k, @env.get_env_var(k)))
    @env.unset_env_var(k)
  }
  saved
}

///|
/// 按快照恢复环境变量。
fn restore_env(saved : Array[(String, String?)]) -> Unit {
  for pair in saved {
    let (k, v) = pair
    match v {
      Some(val) => @env.set_env_var(k, val)
      None => @env.unset_env_var(k)
    }
  }
}

///|
/// 把 TOML 内容写入临时文件并加载，加载后立即删除临时文件。
fn load_toml_str(tag : String, content : String) -> @config.AgentConfig {
  let path = "__diff_harness_tmp_" + tag + ".toml"
  @fs.write_string_to_file(path, content) catch {
    _ => abort("write tmp toml failed: " + tag)
  }
  let config = @config.AgentConfig::load(path) catch {
    _ => abort("AgentConfig::load failed: " + tag)
  }
  @fs.remove_file(path) catch {
    _ => ()
  }
  config
}

///|
/// 保证不存在的配置文件路径（用于"无配置文件"用例）。
let nonexistent_config_path : String = "__diff_harness_nonexistent_config.toml"

// ── config_loading ───────────────────────────────────────────────────────────

///|
/// config-001：从空配置文件加载应返回默认配置。
/// 期望值冻结自 ruby_output（实测）：max_tokens=16384, enable_compression=true,
/// compression_threshold=150000, permission_mode=confirm_safes。应绿。
test "config_001_default_from_empty_config" {
  let config = load_toml_str("001", "")
  assert_eq(config.max_tokens, 16384)
  assert_true(config.enable_compression)
  assert_eq(config.compression_threshold, 150000)
  assert_true(config.permission_mode == @config.ConfirmSafes)
}

///|
/// config-002：从 TOML 文件加载基本配置。
/// 期望值冻结自 ruby_output（实测）。Ruby 的 CONFIG_SETTINGS_KEYS 不含 max_tokens，
/// 不从配置文件加载（BUG-0012）；Ruby 侧 anthropic_format 未设置（nil），
/// MB 侧为 false（BUG-0013，nil 无法在 MB 的 Bool 上表达为断言，仅注释冻结）。
test "config_002_load_basic_settings_and_model" {
  let content =
    #|[settings]
    #|max_tokens = 8192
    #|enable_compression = false
    #|compression_threshold = 100000
    #|
    #|[[models]]
    #|id = "test-model"
    #|api_key = "sk-test"
    #|base_url = "https://api.example.com"
    #|model = "gpt-4"
  let config = load_toml_str("002", content)
  // 两侧一致部分（green）
  assert_true(!config.enable_compression)
  assert_eq(config.compression_threshold, 100000)
  assert_eq(config.models.length(), 1)
  assert_eq(config.models[0].api_key, "sk-test")
  assert_eq(config.models[0].base_url, "https://api.example.com")
  assert_eq(config.models[0].model, "gpt-4")
  // BUG-0013：Ruby anthropic_format 为 nil（未设置），MB 为 false。
  // nil 语义在 MB 的 Bool 字段上不可表达，此处仅注释冻结，不断言。
  // BUG-0012：Ruby 不从配置文件加载 max_tokens，冻结值 16384。
  // 证据：cases/config_cli/test_cases.json config-002
  if known_failure("BUG-0012") {
    return
  }
  assert_eq(config.max_tokens, 16384)
}

///|
/// config-010：配置文件模型缺少必填字段（base_url/model）应跳过该模型。
/// 期望值冻结自 ruby_output（实测）：models_count=0。应绿。
test "config_010_incomplete_model_skipped" {
  let content =
    #|[[models]]
    #|id = "test"
    #|api_key = "sk-test"
  let config = load_toml_str("010", content)
  assert_eq(config.models.length(), 0)
}

///|
/// config-012：配置文件未指定 anthropic_format 的默认值。
/// 期望值冻结自 ruby_output：Ruby 的 default_anthropic_format 在环境变量
/// 未设置时返回 true；MB 从 TOML 解析时默认 false（BUG-0013，known-failure）。
test "config_012_anthropic_format_default" {
  let content =
    #|[[models]]
    #|id = "test"
    #|api_key = "sk-test"
    #|base_url = "https://api.test.com"
    #|model = "gpt-4"
  let config = load_toml_str("012", content)
  assert_eq(config.models.length(), 1)
  // BUG-0013：Ruby 冻结值 anthropic_format=true，MB 实际为 false。
  // 证据：cases/config_cli/test_cases.json config-012
  if known_failure("BUG-0013") {
    return
  }
  assert_true(config.models[0].anthropic_format)
}

///|
/// config-017：permission_mode 枚举值解析。
/// Ruby 用小写字符串 "auto_approve"，MB 用 PascalCase AutoApprove，
/// 语义相同（BUG-0021 wontfix）。冻结 MB 行为：解析为 AutoApprove 且
/// 序列化形式与 Ruby 字符串一致。
test "config_017_permission_mode_auto_approve" {
  let config = load_toml_str(
    "017", "[settings]\npermission_mode = \"auto_approve\"",
  )
  // wontfix（BUG-0021）：枚举表示形式不同但语义相同，冻结 MB 行为。
  assert_true(config.permission_mode == @config.AutoApprove)
  assert_eq(config.permission_mode.to_string_value(), "auto_approve")
}

///|
/// config-018：无效的 permission_mode 应回退默认值 confirm_safes。
/// 期望值冻结自 ruby_output（实测）。应绿。
test "config_018_invalid_permission_mode_falls_back" {
  let config = load_toml_str(
    "018", "[settings]\npermission_mode = \"invalid_mode\"",
  )
  assert_true(config.permission_mode == @config.ConfirmSafes)
}

// ── env_overlay ──────────────────────────────────────────────────────────────

///|
/// config-003：配置文件有模型时同时设置 CLACKY_* 环境变量。
/// 期望值冻结自 ruby_output（实测）：Ruby 仍追加环境变量模型，
/// current 保持文件模型（sk-file），models_count=2。
/// MB 实际行为：merge_config 用环境变量模型整体替换文件模型
/// （current=sk-env，count=1）——BUG-0015 known-failure。
/// 注：用例中的 moonbit_output（current=sk-file, count=1）为 Python 模拟，
/// 与代码实测不符，不采用。
test "config_003_env_overlay_with_file_model" {
  let saved = clear_and_save_env()
  @env.set_env_var("CLACKY_API_KEY", "sk-env")
  @env.set_env_var("CLACKY_BASE_URL", "https://api.env.com")
  @env.set_env_var("CLACKY_MODEL", "gpt-4-turbo")
  let content =
    #|[[models]]
    #|id = "file-model"
    #|api_key = "sk-file"
    #|base_url = "https://api.file.com"
    #|model = "gpt-4"
  let path = "__diff_harness_tmp_003.toml"
  @fs.write_string_to_file(path, content) catch {
    _ => abort("write tmp toml failed: 003")
  }
  let config = @config.AgentConfig::load_with_env(path) catch {
    _ => abort("load_with_env failed: 003")
  }
  @fs.remove_file(path) catch {
    _ => ()
  }
  restore_env(saved)
  // green：环境变量确实参与了加载（MB 侧环境变量模型成为唯一模型）
  assert_eq(config.models.length(), 1)
  // BUG-0015：Ruby 冻结值——current 保持文件模型且 models_count=2。
  // 证据：cases/config_cli/test_cases.json config-003
  if known_failure("BUG-0015") {
    return
  }
  assert_eq(config.models.length(), 2)
  match config.current_model() {
    Some(m) => assert_eq(m.api_key, "sk-file")
    None => abort("current_model should exist")
  }
}

///|
/// config-004：无配置文件时从 CLACKY_* 环境变量加载。
/// 期望值冻结自 ruby_output（实测）：current=env 模型、anthropic_format=true、
/// count=1。MB env 路径会设置 current_model_id=Some("default")（BUG-0014 在
/// env 路径不成立，green）。env_source 为 MB 扩展字段（BUG-0019 wontfix），
/// 冻结其存在性与取值 "env"。
test "config_004_env_only_loading" {
  let saved = clear_and_save_env()
  @env.set_env_var("CLACKY_API_KEY", "sk-env-only")
  @env.set_env_var("CLACKY_BASE_URL", "https://api.env-only.com")
  @env.set_env_var("CLACKY_MODEL", "claude-sonnet-4-5")
  let config = @config.AgentConfig::load_with_env(nonexistent_config_path) catch {
    _ => abort("load_with_env failed: 004")
  }
  restore_env(saved)
  assert_eq(config.models.length(), 1)
  match config.current_model() {
    Some(m) => {
      assert_eq(m.api_key, "sk-env-only")
      assert_eq(m.base_url, "https://api.env-only.com")
      assert_eq(m.model, "claude-sonnet-4-5")
      assert_true(m.anthropic_format)
    }
    None => abort("current_model should exist")
  }
  // env 路径下 MB 会自动设置 current_model_id（BUG-0014 仅存在于纯 TOML 路径）
  assert_eq(config.current_model_id, Some("default"))
  // wontfix（BUG-0019）：env_source 是 MB 扩展字段，冻结其存在性与取值。
  assert_eq(config.env_source, "env")
}

///|
/// config-005：MBOPENCLACKY_* 环境变量兼容层（MB 扩展，Ruby 不支持）。
/// BUG-0016 wontfix，冻结 MB 当前行为。注意：apply_env_overlay 不设置
/// env_source，load_with_env 中 env_source 保持 "toml"——用例 JSON 中的
/// env_source="env" 是 Python 模拟值，不可信，此处按代码实测冻结 "toml"。
test "config_005_mbopenclacky_prefix_compat" {
  let saved = clear_and_save_env()
  @env.set_env_var("MBOPENCLACKY_API_KEY", "sk-mb")
  @env.set_env_var("MBOPENCLACKY_BASE_URL", "https://api.mb.com")
  @env.set_env_var("MBOPENCLACKY_MODEL", "gpt-4")
  let config = @config.AgentConfig::load_with_env(nonexistent_config_path) catch {
    _ => abort("load_with_env failed: 005")
  }
  restore_env(saved)
  // wontfix（BUG-0016）：MB 扩展功能，冻结 MB 当前行为。
  assert_eq(config.models.length(), 1)
  match config.current_model() {
    Some(m) => {
      assert_eq(m.api_key, "sk-mb")
      assert_eq(m.base_url, "https://api.mb.com")
      assert_eq(m.model, "gpt-4")
      // MBOPENCLACKY_ANTHROPIC_FORMAT 未设置时默认 true
      assert_true(m.anthropic_format)
    }
    None => abort("current_model should exist")
  }
  assert_eq(config.env_source, "toml")
}

///|
/// config-006：CLACKY_* 优先级高于 OPENCLACKY_*（MB 扩展，Ruby 不支持
/// OPENCLACKY_* 前缀）。BUG-0017 wontfix，冻结 MB 当前行为。
test "config_006_clacky_priority_over_openclacky" {
  let saved = clear_and_save_env()
  @env.set_env_var("CLACKY_API_KEY", "sk-clacky")
  @env.set_env_var("OPENCLACKY_API_KEY", "sk-openclacky")
  let config = @config.AgentConfig::load_with_env(nonexistent_config_path) catch {
    _ => abort("load_with_env failed: 006")
  }
  restore_env(saved)
  // wontfix（BUG-0017）：OPENCLACKY_* 为 MB 扩展，冻结 MB 优先级行为。
  match config.current_model() {
    Some(m) => assert_eq(m.api_key, "sk-clacky")
    None => abort("current_model should exist")
  }
  assert_eq(config.env_source, "env")
}

///|
/// config-015：CLAUDE_* 环境变量兼容层（MB 扩展，Ruby 侧 ClaudeCode 支持已禁用）。
/// BUG-0018 wontfix，冻结 MB 当前行为（最低优先级兼容层，anthropic_format=true，
/// env_source="claude_compat"）。
test "config_015_claude_prefix_compat" {
  let saved = clear_and_save_env()
  @env.set_env_var("CLAUDE_API_KEY", "sk-claude")
  @env.set_env_var("CLAUDE_BASE_URL", "https://api.claude.com")
  @env.set_env_var("CLAUDE_MODEL", "claude-3-opus")
  let config = @config.AgentConfig::load_with_env(nonexistent_config_path) catch {
    _ => abort("load_with_env failed: 015")
  }
  restore_env(saved)
  // wontfix（BUG-0018）：MB 扩展功能，冻结 MB 当前行为。
  match config.current_model() {
    Some(m) => {
      assert_eq(m.api_key, "sk-claude")
      assert_eq(m.base_url, "https://api.claude.com")
      assert_eq(m.model, "claude-3-opus")
      assert_true(m.anthropic_format)
    }
    None => abort("current_model should exist")
  }
  assert_eq(config.env_source, "claude_compat")
}

///|
/// config-019：CLACKY_ANTHROPIC_FORMAT=false 应使 anthropic_format=false。
/// 期望值冻结自 ruby_output（实测）：false。
/// MB 实际行为：try_load_with_prefix 硬编码 anthropic_format=true，从不读取
/// CLACKY_ANTHROPIC_FORMAT——与 Ruby 不一致。该差异与 BUG-0013
/// （anthropic_format 默认值/来源处理不一致）同根因族，已独立立项为
/// BUG-0052，见 BUGS.md。
test "config_019_clacky_anthropic_format_env" {
  let saved = clear_and_save_env()
  @env.set_env_var("CLACKY_API_KEY", "sk-test")
  @env.set_env_var("CLACKY_ANTHROPIC_FORMAT", "false")
  let config = @config.AgentConfig::load_with_env(nonexistent_config_path) catch {
    _ => abort("load_with_env failed: 019")
  }
  restore_env(saved)
  assert_eq(config.models.length(), 1)
  // BUG-0052：Ruby 冻结值 anthropic_format=false，
  // MB 实际为 true（未读取 CLACKY_ANTHROPIC_FORMAT）。
  // 证据：cases/config_cli/test_cases.json config-019
  if known_failure("BUG-0052") {
    return
  }
  assert_true(!config.models[0].anthropic_format)
}

// ── model_switching ──────────────────────────────────────────────────────────

///|
/// config-007：switch_model_by_id 切换模型。
/// 期望值冻结自 ruby_output（实测）。应绿。
test "config_007_switch_model_by_id" {
  let content =
    #|[[models]]
    #|id = "model-1"
    #|api_key = "sk-1"
    #|base_url = "https://api.1.com"
    #|model = "gpt-4"
    #|type = "default"
    #|
    #|[[models]]
    #|id = "model-2"
    #|api_key = "sk-2"
    #|base_url = "https://api.2.com"
    #|model = "gpt-4-turbo"
  let config = load_toml_str("007", content)
  match config.switch_model_by_id("model-2") {
    Ok(_) => ()
    Err(msg) => abort("switch failed: " + msg)
  }
  assert_eq(config.current_model_id, Some("model-2"))
  match config.current_model() {
    Some(m) => {
      assert_eq(m.api_key, "sk-2")
      assert_eq(m.model, "gpt-4-turbo")
    }
    None => abort("current_model should exist")
  }
}

///|
/// config-008：switch_model_by_name 按显示名切换模型。
/// 期望值冻结自 ruby_output（实测）。应绿。
test "config_008_switch_model_by_name" {
  let content =
    #|[[models]]
    #|id = "model-1"
    #|api_key = "sk-1"
    #|base_url = "https://api.1.com"
    #|model = "gpt-4"
    #|type = "default"
    #|
    #|[[models]]
    #|id = "model-2"
    #|api_key = "sk-2"
    #|base_url = "https://api.2.com"
    #|model = "gpt-4-turbo"
  let config = load_toml_str("008", content)
  match config.switch_model_by_name("gpt-4-turbo") {
    Ok(_) => ()
    Err(msg) => abort("switch failed: " + msg)
  }
  match config.current_model() {
    Some(m) => {
      assert_eq(m.api_key, "sk-2")
      assert_eq(m.model, "gpt-4-turbo")
    }
    None => abort("current_model should exist")
  }
}

///|
/// config-009：switch_model_by_id 切换到不存在的 ID。
/// green：返回错误且 current_model 仍指向原模型（单模型回退两侧一致）。
/// BUG-0020 known-failure：Ruby 错误消息为 "model not found"，
/// MB 为 "model not found with id: non-existent"。
test "config_009_switch_model_by_id_not_found" {
  let content =
    #|[[models]]
    #|id = "model-1"
    #|api_key = "sk-1"
    #|base_url = "https://api.1.com"
    #|model = "gpt-4"
  let config = load_toml_str("009", content)
  let err_msg = match config.switch_model_by_id("non-existent") {
    Ok(_) => abort("switch should fail")
    Err(msg) => msg
  }
  // green：失败后 current_model 仍返回之前的模型（单模型回退）
  match config.current_model() {
    Some(m) => assert_eq(m.id, "model-1")
    None => abort("current_model should remain")
  }
  // BUG-0020：Ruby 冻结错误消息 "model not found"。
  // 证据：cases/config_cli/test_cases.json config-009
  if known_failure("BUG-0020") {
    return
  }
  assert_eq(err_msg, "model not found")
}

///|
/// config-013：多模型配置选择 type=default 的模型作为当前模型。
/// 期望值冻结自 ruby_output（实测）。应绿。
test "config_013_default_badge_wins" {
  let content =
    #|[[models]]
    #|id = "model-1"
    #|api_key = "sk-1"
    #|base_url = "https://api.1.com"
    #|model = "gpt-4"
    #|
    #|[[models]]
    #|id = "model-2"
    #|api_key = "sk-2"
    #|base_url = "https://api.2.com"
    #|model = "gpt-4-turbo"
    #|type = "default"
  let config = load_toml_str("013", content)
  match config.current_model() {
    Some(m) => assert_eq(m.model, "gpt-4-turbo")
    None => abort("current_model should exist")
  }
}

///|
/// config-014：无 type=default 标记时应选择第一个模型。
/// 期望值冻结自 ruby_output（实测）：current.model = "gpt-4"（第一个模型）。
/// MB 实际行为：current_model() 在无 badge 且 current_model_id 为 None 时，
/// 仅当模型数恰为 1 才返回模型，否则返回 None——与 Ruby 不一致。
/// 根因与 BUG-0014（current_model_id 未自动设置）相同：TOML 加载路径不设置
/// current_model_id，导致 current_model() 无法定位。台账未对本用例单独立项，
/// 暂挂 BUG-0014 known-failure，见 BUGS.md。
test "config_014_first_model_when_no_default" {
  let content =
    #|[[models]]
    #|id = "model-1"
    #|api_key = "sk-1"
    #|base_url = "https://api.1.com"
    #|model = "gpt-4"
    #|
    #|[[models]]
    #|id = "model-2"
    #|api_key = "sk-2"
    #|base_url = "https://api.2.com"
    #|model = "gpt-4-turbo"
  let config = load_toml_str("014", content)
  assert_eq(config.models.length(), 2)
  // BUG-0014（扩展证据 config-014）：Ruby 冻结值 current.model="gpt-4"，
  // MB 实际 current_model()=None。
  // 证据：cases/config_cli/test_cases.json config-014
  if known_failure("BUG-0014") {
    return
  }
  match config.current_model() {
    Some(m) => assert_eq(m.model, "gpt-4")
    None => abort("current_model should fall back to first model")
  }
}

// ── config_persistence / config_operations ───────────────────────────────────

///|
/// config-011：保存配置后再加载应保持一致。
/// green：enable_compression / compression_threshold / 模型字段均可回读。
/// BUG-0022 known-failure：Ruby 保存时写入 max_tokens 但加载时不读取，
/// 回读后为默认值 16384；MB 保存与加载都包含 max_tokens（回读 4096）。
/// 按判定总则冻结 Ruby 行为（16384）。
test "config_011_save_load_roundtrip" {
  let config = @config.AgentConfig::default()
  config.max_tokens = 4096
  config.enable_compression = false
  config.compression_threshold = 50000
  config.models.push({
    id: "test-model",
    type_: None,
    api_key: "sk-test",
    base_url: "https://api.test.com",
    model: "gpt-4",
    anthropic_format: false,
    runtime_id: "test-model",
    media_type: None,
  })
  let path = "__diff_harness_tmp_011.toml"
  config.save(path) catch {
    _ => abort("save failed: 011")
  }
  let loaded = @config.AgentConfig::load(path) catch {
    _ => abort("load failed: 011")
  }
  @fs.remove_file(path) catch {
    _ => ()
  }
  // green：其余字段回读一致
  assert_true(!loaded.enable_compression)
  assert_eq(loaded.compression_threshold, 50000)
  assert_eq(loaded.models.length(), 1)
  match loaded.current_model() {
    Some(m) => {
      assert_eq(m.api_key, "sk-test")
      assert_eq(m.base_url, "https://api.test.com")
      assert_eq(m.model, "gpt-4")
      assert_true(!m.anthropic_format)
    }
    None => abort("current_model should exist")
  }
  // BUG-0022：Ruby 冻结值——回读后 max_tokens 为默认 16384（加载不读取）。
  // 证据：cases/config_cli/test_cases.json config-011
  if known_failure("BUG-0022") {
    return
  }
  assert_eq(loaded.max_tokens, 16384)
}

///|
/// config-016：deep_copy 后修改副本不影响原配置。
/// 期望值冻结自 ruby_output（实测）。应绿。
test "config_016_deep_copy_independence" {
  let content =
    #|[[models]]
    #|id = "model-1"
    #|api_key = "sk-1"
    #|base_url = "https://api.1.com"
    #|model = "gpt-4"
    #|type = "default"
  let config = load_toml_str("016", content)
  let copy = config.deep_copy()
  copy.current_model_id = Some("model-x")
  copy.models[0].anthropic_format = true
  // 原配置不受影响
  assert_eq(config.current_model_id, None)
  assert_true(!config.models[0].anthropic_format)
  assert_eq(config.models[0].model, "gpt-4")
}

///|
/// config-020：add_model 添加新模型。
/// 期望值冻结自 ruby_output（实测）：models_count=2 且含 model-2。应绿。
test "config_020_add_model" {
  let content =
    #|[[models]]
    #|id = "model-1"
    #|api_key = "sk-1"
    #|base_url = "https://api.1.com"
    #|model = "gpt-4"
  let config = load_toml_str("020", content)
  config.add_model({
    id: "model-2",
    type_: None,
    api_key: "sk-2",
    base_url: "https://api.2.com",
    model: "gpt-4-turbo",
    anthropic_format: false,
    runtime_id: "model-2",
    media_type: None,
  })
  assert_eq(config.models.length(), 2)
  assert_eq(config.models[1].id, "model-2")
  assert_eq(config.models[1].model, "gpt-4-turbo")
}

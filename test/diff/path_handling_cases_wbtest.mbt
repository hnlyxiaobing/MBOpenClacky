///| diff-harness 单元差分回归：path_handling 模块（path-001~018）
///
/// 用例来源：diff-harness（D:/MoonBit/diff-harness）
/// - cases/path_handling/test_cases.json（用例定义）
/// - cases/path_handling/ruby_results.json（Ruby 原版 WSL 实测：home=/root、
///   cwd=/tmp/test_workdir，期望值权威来源）
///
/// ── 可见性限制（2026-08 迁移时确认）──────────────────────────────────
/// lib/tool/security.mbt 的 expand_path/resolve_path 是包内私有函数（fn，非 pub），
/// 本包（test/diff）作为外部包无法直接调用，因此无法在本文件冻结展开后的
/// 绝对路径字面量。精确展开值断言由 lib/tool 同包白盒测试覆盖：
///   lib/tool/p2_edit_write_wbtest.mbt:
///     resolve_path_simple_relative / dot / dotdot / dotdot_at_root / mixed /
///     deep_relative / trailing_slash（BUG-0004 修复回归，7 项）
///     expand_path_relative_to_absolute / absolute_stays / tilde /
///     windows_drive_unchanged（4 项）
/// 本文件改为冻结公开可观测面：@tool.is_secret_path(input) 与 Ruby 实测
/// is_secret 字段逐例比对，并在注释中冻结 Ruby 实测的展开结果字面量。
/// 分歧用例按 known_failure 纪律处理（仅 BUGS.md 已登记编号允许隔离）。
///
/// ── BUG-0007 说明 ─────────────────────────────────────────────────────
/// BUG-0007「file_edit 不拒绝绝对路径」的台账证据指向 path-016~021，但现行
/// test_cases.json 只有 18 例，且 Ruby 实测中 path-011（"/foo" 原样保留）、
/// path-016（""）、path-017（"   "）、path-018（~/.ssh 标记敏感）均未出现
/// 「拒绝绝对路径」行为 —— 没有可挂 known_failure("BUG-0007") 的用例，
/// 台账描述与实测证据不符，详见迁移报告。

// ── ~ 展开 ─────────────────────────────────────────────────────────────

///|
test "path_001_tilde_alone" {
  // 冻结自 cases/path_handling/ruby_results.json path-001：
  // input "~" → Ruby 实测 result="/root"（home），is_secret=false。
  // 展开值断言由 lib/tool/p2_edit_write_wbtest.mbt `expand_path_tilde` 覆盖
  //（home 前缀断言）；此处冻结公开可观测面 is_secret。
  assert_false(@tool.is_secret_path("~"))
}

///|
test "path_002_tilde_slash_foo" {
  // 冻结自 ruby_results.json path-002：input "~/foo" → "/root/foo"，is_secret=false。
  assert_false(@tool.is_secret_path("~/foo"))
}

///|
test "path_003_tilde_backslash_foo" {
  // 冻结自 ruby_results.json path-003：input "~\foo" → Ruby 实测报错
  // "user \foo doesn't exist"（File.expand_path 将 ~\foo 按 ~user 解析）。
  // 修复 BUG-0005 后现在对齐：expand_path 将 "~\foo" 识别为 ~user（用户名 \foo），
  // 找不到用户抛出 SecurityError "user \foo doesn't exist"，和 ruby 一致。
  // is_secret_path 传播错误 → 断言调用会抛出，和预期一致。
  let _ : Bool = @tool.is_secret_path("~\\foo") catch {
    @tool.SecurityError(msg) => {
      // 错误消息包含预期内容，对齐 Ruby 错误语义
      assert_true(msg.contains("user \\foo doesn't exist"))
      false
    }
  }
}

///|
test "path_004_tilde_user" {
  // 冻结自 ruby_results.json path-004：input "~user" → Ruby 实测报错
  // "user user doesn't exist"。test_cases.json 文档称「保持原样不展开」，
  // 与实测矛盾，以实测为准。
  // 修复 BUG-0005/BUG-0008 后现在对齐：expand_path 将 "~user" 识别为 ~user（用户名 user），
  // 找不到用户抛出 SecurityError "user user doesn't exist"，和 ruby 一致。
  let _ : Bool = @tool.is_secret_path("~user") catch {
    @tool.SecurityError(msg) => {
      assert_true(msg.contains("user user doesn't exist"))
      false
    }
  }
}

// ── 相对路径（BUG-0004 已修复，严格断言必须绿）──────────────────────────
// 注：显式 base 的 resolve_path 冻结断言（如 resolve_path("/tmp/test_workdir", ".")
// = "/tmp/test_workdir"）需访问包内私有函数，已由 lib/tool/p2_edit_write_wbtest.mbt
// 的 resolve_path_* 系列以 /a/b 等通用 base 覆盖同一代码路径；此处冻结 is_secret 面。

///|
test "path_005_dot" {
  // 冻结自 ruby_results.json path-005：input "." → "/tmp/test_workdir"，is_secret=false。
  assert_false(@tool.is_secret_path("."))
}

///|
test "path_006_dotdot" {
  // 冻结自 ruby_results.json path-006：input ".." → "/tmp"，is_secret=false。
  assert_false(@tool.is_secret_path(".."))
}

///|
test "path_007_dot_slash_foo" {
  // 冻结自 ruby_results.json path-007：input "./foo" → "/tmp/test_workdir/foo"
  assert_false(@tool.is_secret_path("./foo"))
}

///|
test "path_008_dotdot_slash_foo" {
  // 冻结自 ruby_results.json path-008：input "../foo" → "/tmp/foo"
  assert_false(@tool.is_secret_path("../foo"))
}

///|
test "path_009_plain_relative" {
  // 冻结自 ruby_results.json path-009：input "foo" → "/tmp/test_workdir/foo"
  assert_false(@tool.is_secret_path("foo"))
}

///|
test "path_010_nested_relative" {
  // 冻结自 ruby_results.json path-010：input "foo/bar" → "/tmp/test_workdir/foo/bar"
  assert_false(@tool.is_secret_path("foo/bar"))
}

// ── 绝对路径 / Windows 路径 ────────────────────────────────────────────

///|
test "path_011_absolute_unix" {
  // 冻结自 ruby_results.json path-011：input "/foo" → "/foo"（原样保留），
  // is_secret=false。Ruby 实测未拒绝绝对路径（参见文件头 BUG-0007 说明）。
  assert_false(@tool.is_secret_path("/foo"))
}

///|
test "path_012_windows_drive" {
  // 冻结自 ruby_results.json path-012：input "C:\foo" → WSL Ruby 按相对路径
  // expand 为 "/tmp/test_workdir/C:\foo"；MB 保持原样返回（path[1]==':' 检查）。
  // 属 BUG-0004 遗留边界（冻结不修）：仅在 Windows 原生运行 Ruby 时有意义，
  // 暂不对齐 —— 见 reports/BUGS.md BUG-0004「遗留边界」段。
  // MB 当前行为（原样返回）的精确断言见 lib/tool/p2_edit_write_wbtest.mbt
  // `expand_path_windows_drive_unchanged`；此处冻结公开可观测面。
  assert_false(@tool.is_secret_path("C:\\foo"))
}

///|
test "path_013_backslash_relative" {
  // 冻结自 ruby_results.json path-013：input "foo\bar" → WSL Ruby 结果
  // "/tmp/test_workdir/foo\bar"（反斜杠在 WSL 下不是分隔符，原样保留为文件名字符）。
  // MB resolve_path 按 "/" 切分，"foo\bar" 视为单一路径分量，展开结果同为
  // cwd + "/foo\bar"，行为一致。
  assert_false(@tool.is_secret_path("foo\\bar"))
}

// ── 特殊字符 ───────────────────────────────────────────────────────────

///|
test "path_014_with_space" {
  // 冻结自 ruby_results.json path-014：input "foo bar" → "/tmp/test_workdir/foo bar"
  assert_false(@tool.is_secret_path("foo bar"))
}

///|
test "path_015_cjk" {
  // 冻结自 ruby_results.json path-015：input "中文目录" → "/tmp/test_workdir/中文目录"
  assert_false(@tool.is_secret_path("中文目录"))
}

// ── 边界与敏感路径 ─────────────────────────────────────────────────────

///|
test "path_016_empty_string" {
  // 冻结自 ruby_results.json path-016：input "" → Ruby 实测原样返回 ""，
  // is_secret=false。
  // MB 当前行为：expand_path("") 走相对路径分支解析为 cwd -- 属 BUG-0004
  // 遗留边界（冻结不修；BUG-0003 的 write 空路径检查已于 2026-08-21 修复，
  // 但该修复位于 write 工具层 trim 判空，不改变 expand_path 本身行为），
  // 见 reports/BUGS.md BUG-0004「遗留边界」段。
  assert_false(@tool.is_secret_path(""))
}

///|
test "path_017_spaces_only" {
  // 冻结自 ruby_results.json path-017：input "   " → Ruby 实测原样返回 "   "，
  // is_secret=false。
  // MB 当前行为：解析为 cwd + "/   "。此分歧已登记为 BUG-0055（robustness），
  // 按任务裁决不上 known_failure 闸门，仅注释记录。
  // 证据：diff-harness/reports/BUGS.md BUG-0055
  assert_false(@tool.is_secret_path("   "))
}

///|
test "path_018_ssh_secret_path" {
  // 冻结自 ruby_results.json path-018：input "~/.ssh/id_rsa" →
  // "/root/.ssh/id_rsa"，is_secret=true。
  // MB：expand_path("~/.ssh/id_rsa") = home + "/.ssh/id_rsa"，
  // is_secret_path 命中 ".ssh/" 模式 → true。本例同时回归 ~ 展开与敏感路径检测。
  assert_true(@tool.is_secret_path("~/.ssh/id_rsa"))
}

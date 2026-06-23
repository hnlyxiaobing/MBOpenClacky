///| File ignore helper — integrates gitignore + builtin + custom rules.

///|
/// Ignore configuration combining multiple rule sources.
pub struct IgnoreConfig {
  gitignore_rules : Array[IgnoreRule] // from .gitignore file
  custom_rules : Array[IgnoreRule] // user-defined rules
  builtin_rules : Array[IgnoreRule] // always-ignore rules
} derive(Debug)

///|
/// Create a new IgnoreConfig with default builtin rules.
pub fn IgnoreConfig::new() -> IgnoreConfig {
  let patterns = builtin_ignore_patterns()
  let builtin_rules : Array[IgnoreRule] = []
  for pat in patterns {
    match parse_rule(pat) {
      Some(rule) => builtin_rules.push(rule)
      None => ()
    }
  }
  { gitignore_rules: [], custom_rules: [], builtin_rules }
}

///|
/// Return the list of builtin ignore patterns (always ignored).
pub fn builtin_ignore_patterns() -> Array[String] {
  [
    ".git", "node_modules", "__pycache__", ".DS_Store", "*.pyc", ".env", ".mooncakes",
    "_build", "target", "dist", ".next", ".svn", ".hg", "*.swp", "*.swo", "Thumbs.db",
  ]
}

///|
/// Load rules from .gitignore file content.
pub fn IgnoreConfig::load_gitignore(
  self : IgnoreConfig,
  content : String,
) -> IgnoreConfig {
  let rules = parse_gitignore(content)
  {
    gitignore_rules: rules,
    custom_rules: self.custom_rules,
    builtin_rules: self.builtin_rules,
  }
}

///|
/// Add a custom ignore pattern.
pub fn IgnoreConfig::add_custom_pattern(
  self : IgnoreConfig,
  pattern : String,
) -> IgnoreConfig {
  let new_custom = self.custom_rules.copy()
  match parse_rule(pattern) {
    Some(rule) => new_custom.push(rule)
    None => ()
  }
  {
    gitignore_rules: self.gitignore_rules,
    custom_rules: new_custom,
    builtin_rules: self.builtin_rules,
  }
}

///|
/// Check if a path should be ignored.
/// Priority: negation rules in gitignore can override; builtin < custom < gitignore ordering.
/// All rule sets are merged and evaluated in order: builtin, custom, gitignore (last wins).
pub fn IgnoreConfig::should_ignore(
  self : IgnoreConfig,
  path : String,
  is_dir? : Bool = false,
) -> Bool {
  // Merge all rules: builtin first, then custom, then gitignore (last wins)
  let all_rules : Array[IgnoreRule] = []
  for rule in self.builtin_rules {
    all_rules.push(rule)
  }
  for rule in self.custom_rules {
    all_rules.push(rule)
  }
  for rule in self.gitignore_rules {
    all_rules.push(rule)
  }
  is_ignored(path, all_rules, is_dir~)
}

///|
/// Filter a list of paths, returning only those NOT ignored.
pub fn IgnoreConfig::filter_paths(
  self : IgnoreConfig,
  paths : Array[String],
) -> Array[String] {
  let result : Array[String] = []
  for p in paths {
    if !self.should_ignore(p) {
      result.push(p)
    }
  }
  result
}

///|
/// Return the reason a path is ignored (the matching rule pattern), or None.
pub fn IgnoreConfig::ignore_reason(
  self : IgnoreConfig,
  path : String,
) -> String? {
  // Check in reverse priority order to find the last matching rule
  let all_rules : Array[IgnoreRule] = []
  for rule in self.builtin_rules {
    all_rules.push(rule)
  }
  for rule in self.custom_rules {
    all_rules.push(rule)
  }
  for rule in self.gitignore_rules {
    all_rules.push(rule)
  }
  let mut last_match : String? = None
  let mut ignored = false
  for rule in all_rules {
    if matches_rule(path, rule) {
      if rule.is_negation {
        ignored = false
        last_match = None
      } else {
        ignored = true
        last_match = Some(rule.pattern)
      }
    }
  }
  if ignored {
    last_match
  } else {
    None
  }
}

///|
/// Return rule count statistics: (gitignore_count, custom_count, builtin_count).
pub fn IgnoreConfig::stats(self : IgnoreConfig) -> (Int, Int, Int) {
  (
    self.gitignore_rules.length(),
    self.custom_rules.length(),
    self.builtin_rules.length(),
  )
}

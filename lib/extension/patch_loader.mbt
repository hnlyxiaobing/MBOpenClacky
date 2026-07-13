///| Extension-side patch loader: convert `ExtensionContribution::Patch`

///| entries into `PatchRule` values that can be folded into an

///| `Agent`'s `PatchChain`.
///
/// Declarative rules live in the contribution's `config` map. The
/// recognized keys are:
///
///   * `tool`        — glob pattern for the tool name (e.g. `terminal`,
///                     `file_*`, `*`). Default: `*`.
///   * `block_pattern` — substring that, when present in the serialized
///                     args, triggers a block. The action becomes
///                     `Block(<reason>)` where `<reason>` is the
///                     contribution's `description` (or `name`).
///   * `allow_pattern` — substring that forces an `Allow` decision
///                     (negative rule: "even if another block matches,
///                     this is fine"). Optional.
///
/// Imperative rules use the contribution's `path` to point at a shell
/// script. The script receives the tool name and args via
/// `CLACKY_PATCH_*` env vars and must print `BLOCK` (optionally
/// followed by a reason) or `ALLOW` to stdout. A non-zero exit code
/// is treated as `ALLOW` (fail-open) so a broken hook can never lock
/// the agent out.
///
/// Reference: openclacky/lib/clacky/extension/patch_loader.rb (concept).

///|

///|
/// Build a `PatchRule` from a single `Patch` contribution.
///
/// Returns `None` when the contribution is not actually a `Patch`
/// type, has no resolvable `config` or `path` (i.e. nothing to do),
/// or has a malformed declarative rule that cannot be interpreted.
pub fn patch_rule_from_contribution(
  ext : Extension,
  contrib : ExtensionContribution,
) -> @agent.PatchRule? {
  // Only Patch contributions produce a rule.
  if contrib.type_ != Patch {
    return None
  }
  let name = if contrib.name != "" { contrib.name } else { contrib.id }
  let tool_pattern = match contrib.config.get("tool") {
    Some(s) if s != "" => s
    _ => "*"
  }
  let has_declarative = contrib.config.contains("block_pattern") ||
    contrib.config.contains("allow_pattern")
  let has_imperative = contrib.path != ""
  if !has_declarative && !has_imperative {
    // Nothing actionable — skip rather than emit a vacuous Allow.
    return None
  }
  let action = match contrib.config.get("block_pattern") {
    Some(pat) if pat != "" =>
      @agent.Block(
        if contrib.description != "" {
          contrib.description
        } else if name != "" {
          "blocked by patch '\{name}'"
        } else {
          "blocked by patch"
        },
      )
    _ => @agent.Allow
  }
  // Args-pattern only meaningful when there's a declarative decision.
  let args_pattern = match contrib.config.get("block_pattern") {
    Some(pat) => pat
    _ => ""
  }
  Some({
    name,
    source: ext.manifest.id,
    tool_pattern,
    args_pattern,
    action,
    command: if has_imperative {
      contrib.path
    } else {
      ""
    },
  })
}

///|
/// Build a `PatchRule` array from every `Patch` contribution in `ext`.
///
/// Order matches the contribution order in the manifest, so extension
/// authors control chain priority. The returned array may be empty.
pub fn patch_rules_from_extension(ext : Extension) -> Array[@agent.PatchRule] {
  let rules : Array[@agent.PatchRule] = []
  for c in ext.manifest.contributions {
    match patch_rule_from_contribution(ext, c) {
      Some(rule) => rules.push(rule)
      None => ()
    }
  }
  rules
}

///|
/// Fold every enabled extension's `Patch` contributions into a single
/// `PatchChain` ready to attach to an `Agent`.
///
/// Disabled extensions (`ext.enabled == false`) are skipped, so the
/// caller can pass the result of `load_all_extensions()` directly
/// without filtering.
pub fn build_patch_chain(extensions : Array[Extension]) -> @agent.PatchChain {
  let chain = @agent.PatchChain::new()
  for ext in extensions {
    if !ext.enabled {
      continue
    }
    for rule in patch_rules_from_extension(ext) {
      chain.add_rule(rule)
    }
  }
  chain
}

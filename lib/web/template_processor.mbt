///| Template preprocessing for static HTML files.

///| Replaces placeholder tokens with runtime values:

///| - {{BRAND_NAME}} -> configured brand name

///| - {{EXT_SCRIPTS}} -> injected extension script tags

///|
/// Configuration for template preprocessing.
pub(all) struct TemplateConfig {
  brand_name : String
  panel_agents_script : String
  global_ext_script_tags : String
  agent_webui_script_tags : String
  official_panel_script_tags : String
}

///|
/// Create a default template configuration.
pub fn TemplateConfig::default() -> TemplateConfig {
  // Read brand name from brand config (fallback to "MBOpenClacky")
  let brand_name = resolve_brand_name()
  // Build official panel script tags for git and time_machine
  let official_tags = build_official_panel_script_tags()
  {
    brand_name,
    panel_agents_script: "",
    global_ext_script_tags: "",
    agent_webui_script_tags: "",
    official_panel_script_tags: official_tags,
  }
}

///|
/// Resolve the brand name from the brand config directory.
/// Falls back to "MBOpenClacky" if the config is unavailable.
fn resolve_brand_name() -> String {
  let dir = match @utils.config_dir() {
    Some(d) => d
    None =>
      match @utils.home_dir() {
        Some(home) =>
          @path.Path(home).join(@path.Path(".mbopenclacky/brand")).to_string()
        None => ".mbopenclacky/brand"
      }
  }
  let cfg = @brand.BrandConfig::load(dir)
  let name = cfg.display_name()
  if name.is_empty() {
    "MBOpenClacky"
  } else {
    name
  }
}

///|
/// Build script tags for official ext_ui panels.
/// Dynamically discovers enabled extensions with panel contributions and
/// injects `<script src="/ext_ui/<ext_id>/panel.js" defer>` for each whose
/// panel JS asset exists under the static web root. Extensions without a
/// matching file are silently skipped (no 404 on page load).
fn build_official_panel_script_tags() -> String {
  let extensions = @extension.load_all_extensions()
  let tags : Array[String] = []
  for ext in extensions {
    if !ext.enabled {
      continue
    }
    let has_panel = ext.manifest.contributions
      .iter()
      .find_first(fn(c) {
        c.type_ == @extension.ExtensionContributionType::Panel
      })
    match has_panel {
      Some(_) => {
        let panel_path = "web/ext_ui/" + ext.manifest.id + "/panel.js"
        if @fs.path_exists(panel_path) {
          let src = "/ext_ui/" + ext.manifest.id + "/panel.js"
          tags.push("<script src=\"" + src + "\" defer></script>")
        }
      }
      None => ()
    }
  }
  tags.join("\n")
}

///|
/// Process template content by replacing placeholder tokens.
/// Supported placeholders:
/// - `{{BRAND_NAME}}` -> brand name from config
/// - `{{EXT_SCRIPTS}}` -> combined extension script tags
pub fn process_template(content : String, config : TemplateConfig) -> String {
  let ext_scripts = inject_ext_scripts(config)
  let result = content.replace_all(old="{{BRAND_NAME}}", new=config.brand_name)
  result.replace_all(old="{{EXT_SCRIPTS}}", new=ext_scripts)
}

///|
/// Build the combined extension scripts string from all sources.
/// Injection order:
/// 1. Panel agents script (inline)
/// 2. Global extension script tags
/// 3. Agent WebUI script tags
/// 4. Official panel script tags
fn inject_ext_scripts(config : TemplateConfig) -> String {
  let mut result = ""
  if config.panel_agents_script.length() > 0 {
    result = result +
      "<!-- Panel Agents -->\n" +
      config.panel_agents_script +
      "\n"
  }
  if config.global_ext_script_tags.length() > 0 {
    result = result +
      "<!-- Global Extensions -->\n" +
      config.global_ext_script_tags +
      "\n"
  }
  if config.agent_webui_script_tags.length() > 0 {
    result = result +
      "<!-- Agent WebUI -->\n" +
      config.agent_webui_script_tags +
      "\n"
  }
  if config.official_panel_script_tags.length() > 0 {
    result = result +
      "<!-- Official Panels -->\n" +
      config.official_panel_script_tags +
      "\n"
  }
  result
}

///|
/// Read a template file and process it with the given configuration.
/// Returns None if the file cannot be read.
pub fn load_and_process_template(
  file_path : String,
  config : TemplateConfig,
) -> String? {
  if @fs.path_exists(file_path) {
    let content = @fs.read_file_to_string(file_path) catch { _ => return None }
    Some(process_template(content, config))
  } else {
    None
  }
}

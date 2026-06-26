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
  {
    brand_name: "MBOpenClacky",
    panel_agents_script: "",
    global_ext_script_tags: "",
    agent_webui_script_tags: "",
    official_panel_script_tags: "",
  }
}

///|
/// Process template content by replacing placeholder tokens.
/// Supported placeholders:
/// - `{{BRAND_NAME}}` -> brand name from config
/// - `{{EXT_SCRIPTS}}` -> combined extension script tags
pub fn process_template(content : String, config : TemplateConfig) -> String {
  let ext_scripts = inject_ext_scripts(config)
  let result = content.replace(old="{{BRAND_NAME}}", new=config.brand_name)
  result.replace(old="{{EXT_SCRIPTS}}", new=ext_scripts)
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

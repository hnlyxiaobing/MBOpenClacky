///| Extension scaffold: generates a new extension skeleton with manifest
/// and template files for different contribution types.

///|
/// Template configuration for a new extension.
pub(all) struct ExtensionTemplate {
  id : String
  name : String
  version : String
  description : String
  author : String
  license : String
  contributions : Array[ExtensionContributionType]
} derive(Eq)

///|
pub extend ExtensionTemplate with Eq::{not_equal, equal}

///|
/// Create a new extension scaffold from a template.
pub fn create_extension_scaffold(
  template : ExtensionTemplate,
  output_dir~ : String? = None,
) -> Result[String, String] {
  let out_dir = match output_dir {
    Some(d) => d
    None => "./extensions"
  }
  let ext_dir = @path.Path::join(out_dir, @path.Path(template.id)).to_string()
  if @fs.path_exists(ext_dir) {
    return Err("extension directory already exists: " + ext_dir)
  }
  @utils.ensure_dir(ext_dir)
  let contrib_dir = @path.Path::join(ext_dir, @path.Path("contributions")).to_string()
  @utils.ensure_dir(contrib_dir)
  // Generate the manifest.
  let manifest = build_manifest_from_template(template)
  let manifest_path = @path.Path::join(ext_dir, @path.Path("ext.yml")).to_string()
  @fs.write_string_to_file(manifest_path, generate_manifest_json(manifest)) catch {
    e => return Err("failed to write manifest: " + @debug.to_string(e))
  }
  // Generate one template file per contribution type.
  for contrib_type in template.contributions {
    match create_contribution_template(ext_dir, template.id, contrib_type) {
      Ok(_) => ()
      Err(e) => return Err(e)
    }
  }
  // Write a friendly README.
  let readme_path = @path.Path::join(ext_dir, @path.Path("README.md")).to_string()
  @fs.write_string_to_file(readme_path, generate_readme(template)) catch {
    e => return Err("failed to write README: " + @debug.to_string(e))
  }
  Ok(ext_dir)
}

///|
/// Build a manifest from a template.
fn build_manifest_from_template(
  template : ExtensionTemplate,
) -> ExtensionManifest {
  let contributions : Array[ExtensionContribution] = []
  for contrib_type in template.contributions {
    let info = contribution_template_info(contrib_type)
    contributions.push({
      type_: contrib_type,
      id: info.0,
      name: info.1,
      description: info.2,
      path: info.3,
      config: Map([]),
    })
  }
  {
    id: template.id,
    name: template.name,
    version: template.version,
    description: template.description,
    author: template.author,
    license: template.license,
    homepage: None,
    repository: None,
    keywords: ["sample", "extension"],
    dependencies: Map([]),
    contributions,
    enabled_by_default: true,
  }
}

///|
/// Look up the template defaults (id, name, description, path) for a contribution type.
/// The path is relative to the extension root and matches the directory layout
/// produced by `create_extension_scaffold` (files live in `contributions/`).
fn contribution_template_info(
  type_ : ExtensionContributionType,
) -> (String, String, String, String) {
  match type_ {
    ExtensionContributionType::Panel =>
      (
        "main-panel", "Main Panel", "A sample panel contribution", "contributions/panel.json",
      )
    ExtensionContributionType::Skill =>
      (
        "sample-skill", "Sample Skill", "A sample skill contribution", "contributions/skill.json",
      )
    ExtensionContributionType::Agent =>
      (
        "sample-agent", "Sample Agent", "A sample agent contribution", "contributions/agent.json",
      )
    ExtensionContributionType::Api =>
      (
        "sample-api", "Sample API", "A sample API contribution", "contributions/api.json",
      )
    ExtensionContributionType::Hook =>
      (
        "sample-hook", "Sample Hook", "A sample hook contribution", "contributions/hook.json",
      )
    ExtensionContributionType::Patch =>
      (
        "sample-patch", "Sample Patch", "A sample patch contribution", "contributions/patch.json",
      )
  }
}

///|
/// Render the manifest as a JSON string (ext.yml is JSON-formatted for MVP).
fn generate_manifest_json(manifest : ExtensionManifest) -> String {
  let contributions_json : Array[Json] = []
  for contrib in manifest.contributions {
    let type_str = match contrib.type_ {
      ExtensionContributionType::Panel => "panel"
      ExtensionContributionType::Skill => "skill"
      ExtensionContributionType::Agent => "agent"
      ExtensionContributionType::Api => "api"
      ExtensionContributionType::Hook => "hook"
      ExtensionContributionType::Patch => "patch"
    }
    let config_obj : Map[String, Json] = Map([])
    contrib.config.each(fn(k, v) { config_obj[k] = Json(v) })
    contributions_json.push(
      Json::object({
        "type": Json(type_str),
        "id": Json(contrib.id),
        "name": Json(contrib.name),
        "description": Json(contrib.description),
        "path": Json(contrib.path),
        "config": Json::object(config_obj),
      }),
    )
  }
  let manifest_obj : Map[String, Json] = {
    "id": Json(manifest.id),
    "name": Json(manifest.name),
    "version": Json(manifest.version),
    "description": Json(manifest.description),
    "author": Json(manifest.author),
    "license": Json(manifest.license),
    "keywords": Json::array(manifest.keywords.map(fn(k) { Json(k) })),
    "contributions": Json::array(contributions_json),
    "enabled_by_default": Json(manifest.enabled_by_default),
  }
  match manifest.homepage {
    Some(hp) => manifest_obj["homepage"] = Json(hp)
    None => ()
  }
  match manifest.repository {
    Some(repo) => manifest_obj["repository"] = Json(repo)
    None => ()
  }
  let deps_obj : Map[String, Json] = Map([])
  manifest.dependencies.each(fn(k, v) { deps_obj[k] = Json(v) })
  manifest_obj["dependencies"] = Json::object(deps_obj)
  Json::object(manifest_obj).stringify()
}

///|
/// Create a template file for a given contribution type.
fn create_contribution_template(
  ext_dir : String,
  ext_id : String,
  type_ : ExtensionContributionType,
) -> Result[Unit, String] {
  let info = contribution_template_info(type_)
  // info.3 already includes the `contributions/` subdir prefix so the
  // manifest `path` field stays consistent with the file's on-disk location.
  let file_path = @path.Path::join(ext_dir, @path.Path(info.3)).to_string()
  @utils.ensure_dir(@path.Path::dirname(@path.Path(file_path)).to_string())
  let content = match type_ {
    ExtensionContributionType::Panel =>
      generate_panel_template(ext_id, info.0, info.1, info.2)
    ExtensionContributionType::Skill =>
      generate_skill_template(ext_id, info.0, info.1, info.2)
    ExtensionContributionType::Agent =>
      generate_agent_template(ext_id, info.0, info.1, info.2)
    ExtensionContributionType::Api =>
      generate_api_template(ext_id, info.0, info.1, info.2)
    ExtensionContributionType::Hook =>
      generate_hook_template(ext_id, info.0, info.1, info.2)
    ExtensionContributionType::Patch =>
      generate_patch_template(ext_id, info.0, info.1, info.2)
  }
  @fs.write_string_to_file(file_path, content) catch {
    e =>
      return Err(
        "failed to write contribution template to " +
        file_path +
        ": " +
        @debug.to_string(e),
      )
  }
  Ok(())
}

///|
/// Render a panel contribution template.
fn generate_panel_template(
  ext_id : String,
  id : String,
  name : String,
  desc : String,
) -> String {
  let obj : Map[String, Json] = {
    "id": Json(id),
    "name": Json(name),
    "description": Json(desc),
    "type": Json("panel"),
    "extension": Json(ext_id),
    "ui": Json::object({
      "title": Json(name),
      "components": Json::array([
        Json::object({
          "type": Json("text"),
          "content": Json("Welcome to the " + name + " panel!"),
        }),
      ]),
    }),
  }
  Json::object(obj).stringify()
}

///|
/// Render a skill contribution template.
fn generate_skill_template(
  ext_id : String,
  id : String,
  name : String,
  desc : String,
) -> String {
  let obj : Map[String, Json] = {
    "id": Json(id),
    "name": Json(name),
    "description": Json(desc),
    "type": Json("skill"),
    "extension": Json(ext_id),
    "skills": Json::array([
      Json::object({
        "name": Json("sample_action"),
        "description": Json("A sample skill action"),
        "parameters": Json::object(Map([])),
      }),
    ]),
  }
  Json::object(obj).stringify()
}

///|
/// Render an agent contribution template.
fn generate_agent_template(
  ext_id : String,
  id : String,
  name : String,
  desc : String,
) -> String {
  let obj : Map[String, Json] = {
    "id": Json(id),
    "name": Json(name),
    "description": Json(desc),
    "type": Json("agent"),
    "extension": Json(ext_id),
    "config": Json::object({
      "system_prompt": Json(
        "You are a helpful assistant for the " + ext_id + " extension.",
      ),
      "temperature": Json(0.7),
    }),
  }
  Json::object(obj).stringify()
}

///|
/// Render an API contribution template.
fn generate_api_template(
  ext_id : String,
  id : String,
  name : String,
  desc : String,
) -> String {
  let obj : Map[String, Json] = {
    "id": Json(id),
    "name": Json(name),
    "description": Json(desc),
    "type": Json("api"),
    "extension": Json(ext_id),
    "routes": Json::array([
      Json::object({
        "method": Json("GET"),
        "path": Json("/hello"),
        "handler": Json("hello_world"),
        "description": Json("A sample API endpoint"),
      }),
    ]),
  }
  Json::object(obj).stringify()
}

///|
/// Render a hook contribution template.
fn generate_hook_template(
  ext_id : String,
  id : String,
  name : String,
  desc : String,
) -> String {
  let obj : Map[String, Json] = {
    "id": Json(id),
    "name": Json(name),
    "description": Json(desc),
    "type": Json("hook"),
    "extension": Json(ext_id),
    "hooks": Json::array([
      Json::object({
        "event": Json("session_start"),
        "handler": Json("on_session_start"),
        "description": Json("Called when a session starts"),
      }),
    ]),
  }
  Json::object(obj).stringify()
}

///|
/// Render a patch contribution template.
fn generate_patch_template(
  ext_id : String,
  id : String,
  name : String,
  desc : String,
) -> String {
  let obj : Map[String, Json] = {
    "id": Json(id),
    "name": Json(name),
    "description": Json(desc),
    "type": Json("patch"),
    "extension": Json(ext_id),
    "patches": Json::array([
      Json::object({
        "target": Json("some_config"),
        "operation": Json("merge"),
        "value": Json::object({ "enabled": Json(true) }),
      }),
    ]),
  }
  Json::object(obj).stringify()
}

///|
/// Render a README describing the new extension.
fn generate_readme(template : ExtensionTemplate) -> String {
  let contrib_names : Array[String] = []
  for c in template.contributions {
    contrib_names.push(contribution_type_name(c))
  }
  let contrib_list = contrib_names.join(", ")
  "# " +
  template.name +
  "\n" +
  "\n" +
  template.description +
  "\n" +
  "\n" +
  "## Installation\n" +
  "\n" +
  "1. Copy this directory to `~/.clacky/extensions/" +
  template.id +
  "`\n" +
  "2. Restart Clacky\n" +
  "3. Enable the extension in settings\n" +
  "\n" +
  "## Contributions\n" +
  "\n" +
  contrib_list +
  "\n" +
  "\n" +
  "## License\n" +
  "\n" +
  template.license +
  "\n" +
  "\n" +
  "## Author\n" +
  "\n" +
  template.author +
  "\n"
}

///|
/// Human-readable name of a contribution type.
fn contribution_type_name(type_ : ExtensionContributionType) -> String {
  match type_ {
    ExtensionContributionType::Panel => "panel"
    ExtensionContributionType::Skill => "skill"
    ExtensionContributionType::Agent => "agent"
    ExtensionContributionType::Api => "api"
    ExtensionContributionType::Hook => "hook"
    ExtensionContributionType::Patch => "patch"
  }
}

///|
/// Construct a default extension template with reasonable defaults.
pub fn default_template(id : String, name : String) -> ExtensionTemplate {
  {
    id,
    name,
    version: "0.1.0",
    description: "A new Clacky extension",
    author: "Your Name",
    license: "MIT",
    contributions: [
      ExtensionContributionType::Panel,
      ExtensionContributionType::Skill,
    ],
  }
}

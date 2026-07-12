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
/// Create a new extension scaffold from a template.
pub fn create_extension_scaffold(
  template : ExtensionTemplate,
  output_dir? : String? = None,
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
  let contrib_dir = @path.Path::join(
    ext_dir,
    @path.Path("contributions"),
  ).to_string()
  @utils.ensure_dir(contrib_dir)
  // Generate the manifest.
  let manifest = build_manifest_from_template(template)
  let manifest_path = @path.Path::join(ext_dir, @path.Path("ext.yml")).to_string()
  @fs.write_string_to_file(manifest_path, generate_manifest_json(manifest)) catch {
    e => return Err("failed to write manifest: " + e.to_string())
  }
  // Generate one template file per contribution type.
  for contrib_type in template.contributions {
    match create_contribution_template(contrib_dir, template.id, contrib_type) {
      Ok(_) => ()
      Err(e) => return Err(e)
    }
  }
  // Write a friendly README.
  let readme_path = @path.Path::join(ext_dir, @path.Path("README.md")).to_string()
  @fs.write_string_to_file(readme_path, generate_readme(template)) catch {
    e => return Err("failed to write README: " + e.to_string())
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
      config: {},
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
    dependencies: {},
    contributions,
    enabled_by_default: true,
  }
}

///|
/// Look up the template defaults (id, name, description, path) for a contribution type.
fn contribution_template_info(
  type_ : ExtensionContributionType,
) -> (String, String, String, String) {
  match type_ {
    ExtensionContributionType::Panel =>
      ("main-panel", "Main Panel", "A sample panel contribution", "panel.json")
    ExtensionContributionType::Skill =>
      ("sample-skill", "Sample Skill", "A sample skill contribution", "skill.json")
    ExtensionContributionType::Agent =>
      ("sample-agent", "Sample Agent", "A sample agent contribution", "agent.json")
    ExtensionContributionType::Api =>
      ("sample-api", "Sample API", "A sample API contribution", "api.json")
    ExtensionContributionType::Hook =>
      ("sample-hook", "Sample Hook", "A sample hook contribution", "hook.json")
    ExtensionContributionType::Patch =>
      ("sample-patch", "Sample Patch", "A sample patch contribution", "patch.json")
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
    let config_obj : Map[String, Json] = {}
    contrib.config.each(fn(k, v) { config_obj[k] = v.to_json() })
    contributions_json.push(
      Json::object({
        "type": type_str.to_json(),
        "id": contrib.id.to_json(),
        "name": contrib.name.to_json(),
        "description": contrib.description.to_json(),
        "path": contrib.path.to_json(),
        "config": Json::object(config_obj),
      }),
    )
  }
  let manifest_obj : Map[String, Json] = {
    "id": manifest.id.to_json(),
    "name": manifest.name.to_json(),
    "version": manifest.version.to_json(),
    "description": manifest.description.to_json(),
    "author": manifest.author.to_json(),
    "license": manifest.license.to_json(),
    "keywords": Json::array(manifest.keywords.map(fn(k) { k.to_json() })),
    "contributions": Json::array(contributions_json),
    "enabled_by_default": manifest.enabled_by_default.to_json(),
  }
  match manifest.homepage {
    Some(hp) => manifest_obj["homepage"] = hp.to_json()
    None => ()
  }
  match manifest.repository {
    Some(repo) => manifest_obj["repository"] = repo.to_json()
    None => ()
  }
  let deps_obj : Map[String, Json] = {}
  manifest.dependencies.each(fn(k, v) { deps_obj[k] = v.to_json() })
  manifest_obj["dependencies"] = Json::object(deps_obj)
  Json::object(manifest_obj).stringify()
}

///|
/// Create a template file for a given contribution type.
fn create_contribution_template(
  contrib_dir : String,
  ext_id : String,
  type_ : ExtensionContributionType,
) -> Result[Unit, String] {
  let info = contribution_template_info(type_)
  let file_path = @path.Path::join(
    contrib_dir,
    @path.Path(info.3),
  ).to_string()
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
    e => return Err("failed to write contribution template to " + file_path + ": " + e.to_string())
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
    "id": id.to_json(),
    "name": name.to_json(),
    "description": desc.to_json(),
    "type": "panel".to_json(),
    "extension": ext_id.to_json(),
    "ui": Json::object({
      "title": name.to_json(),
      "components": Json::array([
        Json::object({
          "type": "text".to_json(),
          "content": ("Welcome to the " + name + " panel!").to_json(),
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
    "id": id.to_json(),
    "name": name.to_json(),
    "description": desc.to_json(),
    "type": "skill".to_json(),
    "extension": ext_id.to_json(),
    "skills": Json::array([
      Json::object({
        "name": "sample_action".to_json(),
        "description": "A sample skill action".to_json(),
        "parameters": Json::object({}),
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
    "id": id.to_json(),
    "name": name.to_json(),
    "description": desc.to_json(),
    "type": "agent".to_json(),
    "extension": ext_id.to_json(),
    "config": Json::object({
      "system_prompt": ("You are a helpful assistant for the " + ext_id + " extension.").to_json(),
      "temperature": 0.7.to_json(),
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
    "id": id.to_json(),
    "name": name.to_json(),
    "description": desc.to_json(),
    "type": "api".to_json(),
    "extension": ext_id.to_json(),
    "routes": Json::array([
      Json::object({
        "method": "GET".to_json(),
        "path": "/hello".to_json(),
        "handler": "hello_world".to_json(),
        "description": "A sample API endpoint".to_json(),
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
    "id": id.to_json(),
    "name": name.to_json(),
    "description": desc.to_json(),
    "type": "hook".to_json(),
    "extension": ext_id.to_json(),
    "hooks": Json::array([
      Json::object({
        "event": "session_start".to_json(),
        "handler": "on_session_start".to_json(),
        "description": "Called when a session starts".to_json(),
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
    "id": id.to_json(),
    "name": name.to_json(),
    "description": desc.to_json(),
    "type": "patch".to_json(),
    "extension": ext_id.to_json(),
    "patches": Json::array([
      Json::object({
        "target": "some_config".to_json(),
        "operation": "merge".to_json(),
        "value": Json::object({ "enabled": true.to_json() }),
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
  "# " + template.name + "\n" +
  "\n" +
  template.description + "\n" +
  "\n" +
  "## Installation\n" +
  "\n" +
  "1. Copy this directory to `~/.clacky/extensions/" + template.id + "`\n" +
  "2. Restart Clacky\n" +
  "3. Enable the extension in settings\n" +
  "\n" +
  "## Contributions\n" +
  "\n" +
  contrib_list + "\n" +
  "\n" +
  "## License\n" +
  "\n" +
  template.license + "\n" +
  "\n" +
  "## Author\n" +
  "\n" +
  template.author + "\n"
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
    contributions: [ExtensionContributionType::Panel, ExtensionContributionType::Skill],
  }
}
///| Extension scaffold: generates a new extension skeleton with manifest
/// and template files for different contribution types.

use @clacky.extension.types.{
  ExtensionManifest,
  ExtensionContribution,
  ExtensionContributionType,
}
use @path.Path
use @fs
use @utils

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
} derive(Show)

///|
/// Create a new extension scaffold from a template.
pub(all) fn create_extension_scaffold(
  template : ExtensionTemplate,
  output_dir? : String? = None,
) -> Result[String, String] {
  let out_dir = output_dir.unwrap_or("./extensions")
  let ext_dir = Path::join(out_dir, Path(template.id)).to_string()
  
  // Check if directory already exists
  if fs.path_exists(ext_dir) {
    Err("extension directory already exists: \{ext_dir}")?
  }
  
  // Create directory structure
  fs.create_dir_all(ext_dir) catch { e => Err(e.to_string())? }
  
  // Create contributions directory
  let contrib_dir = Path::join(ext_dir, Path("contributions")).to_string()
  fs.create_dir_all(contrib_dir) catch { e => Err(e.to_string())? }
  
  // Generate manifest
  let manifest = create_manifest_from_template(template)
  let manifest_content = generate_manifest_json(manifest)
  let manifest_path = Path::join(ext_dir, Path("ext.yml")).to_string()
  fs.write_string_to_file(manifest_path, manifest_content) catch { e => Err(e.to_string())? }
  
  // Generate contribution template files
  for contrib_type in template.contributions {
    create_contribution_template(contrib_dir, template.id, contrib_type)?
  }
  
  // Create README
  let readme_content = generate_readme(template)
  let readme_path = Path::join(ext_dir, Path("README.md")).to_string()
  fs.write_string_to_file(readme_path, readme_content) catch { e => Err(e.to_string())? }
  
  Ok(ext_dir)
}

///|
/// Create a manifest from a template.
fn create_manifest_from_template(template : ExtensionTemplate) -> ExtensionManifest {
  let contributions : Array[ExtensionContribution] = []
  
  for contrib_type in template.contributions {
    let (id, name, desc, path) = contribution_template_info(contrib_type)
    contributions.push({
      type_: contrib_type,
      id,
      name,
      description: desc,
      path,
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
/// Get template info for a contribution type.
fn contribution_template_info(
  type_ : ExtensionContributionType,
) -> (String, String, String, String) {
  match type_ {
    ExtensionContributionType::Panel =>
      ("main-panel", "Main Panel", "A sample panel contribution", "contributions/panel.json")
    ExtensionContributionType::Skill =>
      ("sample-skill", "Sample Skill", "A sample skill contribution", "contributions/skill.json")
    ExtensionContributionType::Agent =>
      ("sample-agent", "Sample Agent", "A sample agent contribution", "contributions/agent.json")
    ExtensionContributionType::Api =>
      ("sample-api", "Sample API", "A sample API contribution", "contributions/api.json")
    ExtensionContributionType::Hook =>
      ("sample-hook", "Sample Hook", "A sample hook contribution", "contributions/hook.json")
    ExtensionContributionType::Patch =>
      ("sample-patch", "Sample Patch", "A sample patch contribution", "contributions/patch.json")
  }
}

///|
/// Generate manifest JSON content.
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
    contributions_json.push(Json::object({
      "type": type_str.to_json(),
      "id": contrib.id.to_json(),
      "name": contrib.name.to_json(),
      "description": contrib.description.to_json(),
      "path": contrib.path.to_json(),
      "config": Json::object(contrib.config.map_values(fn(v) { v.to_json() })),
    }))
  }
  
  let manifest_obj : Map[String, Json] = {
    "id": manifest.id.to_json(),
    "name": manifest.name.to_json(),
    "version": manifest.version.to_json(),
    "description": manifest.description.to_json(),
    "author": manifest.author.to_json(),
    "license": manifest.license.to_json(),
    "keywords": Json::array(manifest.keywords.map(fn(k) { k.to_json() })),
    "dependencies": Json::object(manifest.dependencies.map_values(fn(v) { v.to_json() })),
    "contributions": Json::array(contributions_json),
    "enabled_by_default": Json::bool(manifest.enabled_by_default),
  }
  
  // Add optional fields
  match manifest.homepage {
    Some(hp) => manifest_obj["homepage"] = hp.to_json()
    None => ()
  }
  match manifest.repository {
    Some(repo) => manifest_obj["repository"] = repo.to_json()
    None => ()
  }
  
  Json::object(manifest_obj).stringify_with_indent(2)
}

///|
/// Create a template file for a contribution.
fn create_contribution_template(
  contrib_dir : String,
  ext_id : String,
  type_ : ExtensionContributionType,
) -> Result[Unit, String] {
  let (id, name, desc, path) = contribution_template_info(type_)
  let file_path = Path::join(contrib_dir, Path(Path::new(path).file_name())).to_string()
  
  let content = match type_ {
    ExtensionContributionType::Panel =>
      generate_panel_template(ext_id, id, name, desc)
    ExtensionContributionType::Skill =>
      generate_skill_template(ext_id, id, name, desc)
    ExtensionContributionType::Agent =>
      generate_agent_template(ext_id, id, name, desc)
    ExtensionContributionType::Api =>
      generate_api_template(ext_id, id, name, desc)
    ExtensionContributionType::Hook =>
      generate_hook_template(ext_id, id, name, desc)
    ExtensionContributionType::Patch =>
      generate_patch_template(ext_id, id, name, desc)
  }
  
  fs.write_string_to_file(file_path, content) catch { e => Err(e.to_string())? }
  Ok(())
}

///|
/// Generate panel template.
fn generate_panel_template(ext_id : String, id : String, name : String, desc : String) -> String {
  "{
  \"id\": \"\{id}\",
  \"name\": \"\{name}\",
  \"description\": \"\{desc}\",
  \"type\": \"panel\",
  \"ui\": {
    \"title\": \"\{name}\",
    \"components\": [
      {
        \"type\": \"text\",
        \"content\": \"Welcome to the \{name} panel!\"
      }
    ]
  }
}"
}

///|
/// Generate skill template.
fn generate_skill_template(ext_id : String, id : String, name : String, desc : String) -> String {
  "{
  \"id\": \"\{id}\",
  \"name\": \"\{name}\",
  \"description\": \"\{desc}\",
  \"type\": \"skill\",
  \"skills\": [
    {
      \"name\": \"sample_action\",
      \"description\": \"A sample skill action\",
      \"parameters\": {}
    }
  ]
}"
}

///|
/// Generate agent template.
fn generate_agent_template(ext_id : String, id : String, name : String, desc : String) -> String {
  "{
  \"id\": \"\{id}\",
  \"name\": \"\{name}\",
  \"description\": \"\{desc}\",
  \"type\": \"agent\",
  \"config\": {
    \"system_prompt\": \"You are a helpful assistant for the \{ext_id} extension.\",
    \"temperature\": 0.7
  }
}"
}

///|
/// Generate API template.
fn generate_api_template(ext_id : String, id : String, name : String, desc : String) -> String {
  "{
  \"id\": \"\{id}\",
  \"name\": \"\{name}\",
  \"description\": \"\{desc}\",
  \"type\": \"api\",
  \"routes\": [
    {
      \"method\": \"GET\",
      \"path\": \"/hello\",
      \"handler\": \"hello_world\",
      \"description\": \"A sample API endpoint\"
    }
  ]
}"
}

///|
/// Generate hook template.
fn generate_hook_template(ext_id : String, id : String, name : String, desc : String) -> String {
  "{
  \"id\": \"\{id}\",
  \"name\": \"\{name}\",
  \"description\": \"\{desc}\",
  \"type\": \"hook\",
  \"hooks\": [
    {
      \"event\": \"session_start\",
      \"handler\": \"on_session_start\",
      \"description\": \"Called when a session starts\"
    }
  ]
}"
}

///|
/// Generate patch template.
fn generate_patch_template(ext_id : String, id : String, name : String, desc : String) -> String {
  "{
  \"id\": \"\{id}\",
  \"name\": \"\{name}\",
  \"description\": \"\{desc}\",
  \"type\": \"patch\",
  \"patches\": [
    {
      \"target\": \"some_config\",
      \"operation\": \"merge\",
      \"value\": {
        \"enabled\": true
      }
    }
  ]
}"
}

///|
/// Generate README for the extension.
fn generate_readme(template : ExtensionTemplate) -> String {
  "# \{template.name}

\{template.description}

## Installation

1. Copy this directory to `~/.clacky/extensions/\{template.id}`
2. Restart Clacky
3. Enable the extension in settings

## Usage

Describe how to use this extension.

## License

\{template.license}

## Author

\{template.author}
"
}

///|
/// Create a default extension template with reasonable defaults.
pub(all) fn default_template(id : String, name : String) -> ExtensionTemplate {
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

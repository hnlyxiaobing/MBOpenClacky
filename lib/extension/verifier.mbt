///| Extension verifier: validates manifest structure, contribution types,
/// dependencies, and resource completeness before installation/publish.

use @clacky.extension.types.{
  Extension,
  ExtensionManifest,
  ExtensionContribution,
  ExtensionContributionType,
  ValidationError,
  ValidationResult,
}
use @clacky.extension.loader.load_all_extensions
use @path.Path
use @fs
use @utils

///|
/// Validate an extension before installation or publish.
pub(all) fn validate_extension(ext : Extension) -> ValidationResult {
  validate_manifest(ext.manifest, ext.root_path)
}

///|
/// Validate an extension manifest and its resources.
pub(all) fn validate_manifest(
  manifest : ExtensionManifest,
  root_path : String,
) -> ValidationResult {
  let errors : Array[ValidationError] = []
  let warnings : Array[String] = []
  
  // Validate required fields
  validate_required_fields(manifest, &errors)
  
  // Validate ID format
  validate_id_format(manifest.id, &errors)
  
  // Validate version format
  validate_version_format(manifest.version, &errors)
  
  // Validate contributions
  validate_contributions(manifest.contributions, root_path, &errors, &warnings)
  
  // Validate dependencies (basic check for MVP)
  validate_dependencies(manifest.dependencies, &errors, &warnings)
  
  // Validate required resources exist
  validate_resources_exist(manifest.contributions, root_path, &errors)
  
  let valid = errors.length() == 0
  { valid, errors, warnings }
}

///|
/// Validate required fields are present and non-empty.
fn validate_required_fields(
  manifest : ExtensionManifest,
  errors : &Array[ValidationError],
) -> Unit {
  if manifest.id.is_empty() {
    errors.push(ValidationError::MissingRequiredField("id"))
  }
  if manifest.name.is_empty() {
    errors.push(ValidationError::MissingRequiredField("name"))
  }
  if manifest.version.is_empty() {
    errors.push(ValidationError::MissingRequiredField("version"))
  }
  if manifest.description.is_empty() {
    errors.push(ValidationError::MissingRequiredField("description"))
  }
  if manifest.author.is_empty() {
    errors.push(ValidationError::MissingRequiredField("author"))
  }
  if manifest.license.is_empty() {
    errors.push(ValidationError::MissingRequiredField("license"))
  }
}

///|
/// Validate extension ID format (lowercase, alphanumeric, dashes).
fn validate_id_format(id : String, errors : &Array[ValidationError]) -> Unit {
  if id.is_empty() {
    return
  }
  
  let valid_chars = fn(c : Char) -> Bool {
    c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-'
  }
  
  let all_valid = id.chars().all(valid_chars)
  if !all_valid {
    errors.push(ValidationError::InvalidField(
      "id",
      "must contain only lowercase letters, numbers, and dashes"
    ))
  }
  
  if id.has_prefix("-") || id.has_suffix("-") {
    errors.push(ValidationError::InvalidField(
      "id",
      "must not start or end with a dash"
    ))
  }
}

///|
/// Validate semantic version format (simple check for MVP).
fn validate_version_format(version : String, errors : &Array[ValidationError]) -> Unit {
  if version.is_empty() {
    return
  }
  
  let parts = version.split(".").to_array()
  if parts.length() < 2 {
    errors.push(ValidationError::InvalidVersion(
      "must be in format major.minor[.patch]"
    ))
    return
  }
  
  for part in parts {
    let all_digits = part.chars().all(fn(c) { c.is_ascii_digit() })
    if !all_digits {
      errors.push(ValidationError::InvalidVersion(
        "version parts must be numbers"
      ))
      return
    }
  }
}

///|
/// Validate extension contributions.
fn validate_contributions(
  contributions : Array[ExtensionContribution],
  root_path : String,
  errors : &Array[ValidationError],
  warnings : &Array[String],
) -> Unit {
  let seen_ids : Map[String, Bool] = {}
  
  for contrib in contributions {
    // Check for duplicate IDs within extension
    if seen_ids.contains_key(contrib.id) {
      errors.push(ValidationError::InvalidField(
        "contributions",
        "duplicate contribution id: \{contrib.id}"
      ))
    }
    seen_ids[contrib.id] = true
    
    // Validate contribution ID format
    if contrib.id.is_empty() {
      errors.push(ValidationError::MissingRequiredField(
        "contribution.id"
      ))
    }
    
    // Validate contribution name
    if contrib.name.is_empty() {
      errors.push(ValidationError::MissingRequiredField(
        "contribution.name"
      ))
    }
    
    // Validate contribution path
    if contrib.path.is_empty() {
      errors.push(ValidationError::MissingRequiredField(
        "contribution.path"
      ))
    }
  }
}

///|
/// Validate dependencies (basic check for MVP).
fn validate_dependencies(
  dependencies : Map[String, String],
  errors : &Array[ValidationError],
  warnings : &Array[String],
) -> Unit {
  // For MVP, we just warn about dependencies, full resolution later
  if dependencies.length() > 0 {
    warnings.push(
      "Dependencies are not automatically resolved in MVP: \{dependencies.keys().join(", ")}"
    )
  }
}

///|
/// Validate that all required resource files exist.
fn validate_resources_exist(
  contributions : Array[ExtensionContribution],
  root_path : String,
  errors : &Array[ValidationError],
) -> Unit {
  for contrib in contributions {
    if contrib.path.is_empty() {
      continue
    }
    
    let resource_path = Path::join(root_path, Path(contrib.path)).to_string()
    if !fs.path_exists(resource_path) {
      errors.push(ValidationError::MissingResource(contrib.path))
    }
  }
}

///|
/// Validate all loaded extensions and return a summary.
pub(all) fn validate_all_extensions() -> Map[String, ValidationResult] {
  let extensions = load_all_extensions()
  let results : Map[String, ValidationResult] = {}
  
  for ext in extensions {
    let result = validate_extension(ext)
    results[ext.manifest.id] = result
  }
  
  results
}

///|
/// Get a human-readable error message from a ValidationError.
pub(all) fn validation_error_message(error : ValidationError) -> String {
  match error {
    ValidationError::MissingRequiredField(field) =>
      "Missing required field: \{field}"
    ValidationError::InvalidField(field, msg) =>
      "Invalid field '\{field}': \{msg}"
    ValidationError::InvalidContributionType(t) =>
      "Invalid contribution type: \{t}"
    ValidationError::MissingResource(path) =>
      "Missing resource: \{path}"
    ValidationError::DependencyConflict(a, b) =>
      "Dependency conflict: \{a} and \{b}"
    ValidationError::InvalidVersion(msg) =>
      "Invalid version: \{msg}"
  }
}

///| Extension verifier: validates manifest structure, contribution types,
/// dependencies, and resource completeness before installation/publish.

///|
/// Validate an extension before installation or publish.
pub fn validate_extension(ext : Extension) -> ValidationResult {
  validate_manifest(ext.manifest, ext.root_path)
}

///|
/// Validate an extension manifest and its resources.
pub fn validate_manifest(
  manifest : ExtensionManifest,
  root_path : String,
) -> ValidationResult {
  let errors : Array[ValidationError] = []
  let warnings : Array[String] = []
  validate_required_fields(manifest, errors)
  validate_id_format(manifest.id, errors)
  validate_version_format(manifest.version, errors)
  validate_contributions(manifest.contributions, root_path, errors, warnings)
  validate_dependencies(manifest.dependencies, errors, warnings)
  validate_resources_exist(manifest.contributions, root_path, errors)
  let valid = errors.length() == 0
  { valid, errors, warnings }
}

///|
/// Validate that all required manifest fields are present and non-empty.
fn validate_required_fields(
  manifest : ExtensionManifest,
  errors : Array[ValidationError],
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
/// Validate extension ID format (lowercase ASCII, digits, dashes; no leading/trailing dash).
fn validate_id_format(id : String, errors : Array[ValidationError]) -> Unit {
  if id.is_empty() {
    return
  }
  let valid_chars = fn(c : Char) -> Bool {
    c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-'
  }
  for c in id {
    if !valid_chars(c) {
      errors.push(
        ValidationError::InvalidField(
          "id", "must contain only lowercase letters, numbers, and dashes",
        ),
      )
      break
    }
  }
  if id.has_prefix("-") || id.has_suffix("-") {
    errors.push(
      ValidationError::InvalidField("id", "must not start or end with a dash"),
    )
  }
}

///|
/// Validate semantic version format. Accepts major.minor or major.minor.patch.
fn validate_version_format(
  version : String,
  errors : Array[ValidationError],
) -> Unit {
  if version.is_empty() {
    return
  }
  let parts : Array[String] = []
  version.split(".").each(fn(p) { parts.push(@debug.to_string(p)) })
  let part_count = parts.length()
  if part_count < 2 || part_count > 3 {
    errors.push(
      ValidationError::InvalidVersion(
        "must be in format major.minor or major.minor.patch",
      ),
    )
    return
  }
  let mut bad = false
  for i = 0; i < parts.length(); i = i + 1 {
    let part = parts[i]
    if part.length() == 0 {
      bad = true
      break
    }
    let mut part_bad = false
    for c in part {
      if !c.is_ascii_digit() {
        part_bad = true
        break
      }
    }
    if part_bad {
      bad = true
      break
    }
  }
  if bad {
    errors.push(
      ValidationError::InvalidVersion("version parts must be non-empty numbers"),
    )
  }
}

///|
/// Validate each contribution: id format, no duplicates, and required fields.
fn validate_contributions(
  contributions : Array[ExtensionContribution],
  _root_path : String,
  errors : Array[ValidationError],
  warnings : Array[String],
) -> Unit {
  let seen_ids : Map[String, Bool] = {}
  for contrib in contributions {
    if seen_ids.contains(contrib.id) {
      errors.push(
        ValidationError::InvalidField(
          "contributions",
          "duplicate contribution id: " + contrib.id,
        ),
      )
    }
    seen_ids[contrib.id] = true
    if contrib.id.is_empty() {
      errors.push(ValidationError::MissingRequiredField("contribution.id"))
    }
    if contrib.name.is_empty() {
      errors.push(ValidationError::MissingRequiredField("contribution.name"))
    }
    if contrib.path.is_empty() {
      errors.push(ValidationError::MissingRequiredField("contribution.path"))
    }
  }
  let _ = warnings
}

///|
/// Validate dependencies. MVP: just warn that automatic resolution is not yet implemented.
fn validate_dependencies(
  dependencies : Map[String, String],
  _errors : Array[ValidationError],
  warnings : Array[String],
) -> Unit {
  if dependencies.length() > 0 {
    let keys = dependencies.keys().collect()
    let joined = keys.join(", ")
    warnings.push(
      "Dependencies are not automatically resolved in MVP: " + joined,
    )
  }
}

///|
/// Validate that all referenced resource files exist on disk.
fn validate_resources_exist(
  contributions : Array[ExtensionContribution],
  root_path : String,
  errors : Array[ValidationError],
) -> Unit {
  for contrib in contributions {
    if contrib.path.is_empty() {
      continue
    }
    let resource_path = @path.Path::join(root_path, @path.Path(contrib.path)).to_string()
    if !@fs.path_exists(resource_path) {
      errors.push(ValidationError::MissingResource(contrib.path))
    }
  }
}

///|
/// Validate all loaded extensions and return a map of id -> ValidationResult.
pub fn validate_all_extensions() -> Map[String, ValidationResult] {
  let extensions = load_all_extensions()
  let results : Map[String, ValidationResult] = {}
  for ext in extensions {
    let result = validate_extension(ext)
    results[ext.manifest.id] = result
  }
  results
}

///|
/// Convert a ValidationError into a human-readable string.
pub fn validation_error_message(error : ValidationError) -> String {
  match error {
    ValidationError::MissingRequiredField(field) =>
      "Missing required field: " + field
    ValidationError::InvalidField(field, msg) =>
      "Invalid field '" + field + "': " + msg
    ValidationError::InvalidContributionType(t) =>
      "Invalid contribution type: " + t
    ValidationError::MissingResource(path) => "Missing resource: " + path
    ValidationError::DependencyConflict(a, b) =>
      "Dependency conflict: " + a + " and " + b
    ValidationError::InvalidVersion(msg) => "Invalid version: " + msg
  }
}

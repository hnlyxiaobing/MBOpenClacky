///| Extension framework types and core data structures.

///| Defines the manifest format, extension types, and state management.

///|
/// Extension source type for three-level discovery.
pub(all) enum ExtensionSource {
  /// Builtin extension from assets/extensions
  Builtin
  /// Installed extension from ~/.clacky/extensions
  Installed
  /// Local project extension from ./extensions
  Local
} derive(Show, Eq)

///|
/// Extension contribution type.
pub(all) enum ExtensionContributionType {
  Panel
  Skill
  Agent
  Api
  Hook
  Patch
} derive(Show, Eq)

///|
/// Extension manifest structure (ext.yml).
/// ext.yml is read as JSON for MVP simplicity; YAML support can be added later.
pub(all) struct ExtensionManifest {
  /// Unique extension identifier
  id : String
  /// Human-readable name
  name : String
  /// Semantic version
  version : String
  /// Short description
  description : String
  /// Author name
  author : String
  /// License
  license : String
  /// Homepage URL (optional)
  homepage : String?
  /// Repository URL (optional)
  repository : String?
  /// Keywords for search
  keywords : Array[String]
  /// Dependencies (extension_id -> version constraint)
  dependencies : Map[String, String]
  /// Contributions provided by this extension
  contributions : Array[ExtensionContribution]
  /// Whether this extension is enabled by default
  enabled_by_default : Bool
}

///|
/// Single extension contribution.
pub(all) struct ExtensionContribution {
  /// Contribution type
  type_ : ExtensionContributionType
  /// Contribution ID (unique within extension)
  id : String
  /// Human-readable name
  name : String
  /// Description
  description : String
  /// Path to the contribution file (relative to extension root)
  path : String
  /// Additional configuration (type-specific)
  config : Map[String, String]
}

///|
/// Loaded extension with metadata and state.
pub(all) struct Extension {
  /// Manifest
  manifest : ExtensionManifest
  /// Source type
  source : ExtensionSource
  /// Root directory path
  root_path : String
  /// Whether the extension is currently enabled
  enabled : Bool
  /// Load timestamp (ms since epoch)
  loaded_at : Int64
  /// SHA256 hash of the extension package (if packaged)
  sha256 : String?
}

///|
/// Validation error type.
pub(all) enum ValidationError {
  MissingRequiredField(String)
  InvalidField(String, String)
  InvalidContributionType(String)
  MissingResource(String)
  DependencyConflict(String, String)
  InvalidVersion(String)
}

///|
/// Validation result.
pub(all) struct ValidationResult {
  valid : Bool
  errors : Array[ValidationError]
  warnings : Array[String]
}

///|
/// Extension registry entry for marketplace.
pub(all) struct RegistryEntry {
  /// Extension ID
  id : String
  /// Latest version
  latest_version : String
  /// All available versions
  versions : Array[String]
  /// Metadata (name, description, author, etc.)
  metadata : Map[String, String]
  /// Installation count
  installs : Int
  /// Publish timestamp (ms since epoch)
  published_at : Int64
}

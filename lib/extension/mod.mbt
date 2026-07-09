///| Extension framework main module.
/// Re-exports all public APIs for the extension framework.

pub use @clacky.extension.types.{
  Extension,
  ExtensionManifest,
  ExtensionSource,
  ExtensionContribution,
  ExtensionContributionType,
  ValidationError,
  ValidationResult,
  RegistryEntry,
}

pub use @clacky.extension.loader.{
  load_all_extensions,
  load_extensions_from_source,
  load_single_extension,
  enabled_extensions,
}

pub use @clacky.extension.verifier.{
  validate_extension,
  validate_manifest,
  validate_all_extensions,
  validation_error_message,
}

pub use @clacky.extension.packager.{
  package_extension,
  unpack_extension,
  list_packaged_extensions,
}

pub use @clacky.extension.scaffold.{
  create_extension_scaffold,
  ExtensionTemplate,
  default_template,
}

pub use @clacky.extension.marketplace.{
  list_marketplace_extensions,
  list_installed_extensions,
  list_local_extensions,
  enable_extension,
  disable_extension,
  install_extension_from_path,
  uninstall_extension,
  publish_extension,
  get_extension_by_id,
}

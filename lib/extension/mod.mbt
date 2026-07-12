///| Extension framework main module.
/// Re-exports the public API of every extension-framework module.
pub fn extension_id(ext : Extension) -> String {
  ext.manifest.id
}

///|
/// Build the canonical source directory for a given source.
pub fn source_dir(source : ExtensionSource) -> String {
  get_source_directory(source)
}
///|
/// White-label brand configuration (from brand.yml)
pub(all) struct BrandConfig {
  product_name : String?
  package_name : String?
  logo_url : String?
  support_contact : String?
  support_qr_url : String?
  theme_color : String?
  homepage_url : String?
  license_key : String?
  license_activated_at : String?
  license_expires_at : String?
  license_last_heartbeat : String?
  device_id : String?
} derive(Eq, Debug, ToJson)

///|
/// Load brand configuration from brand.yml
pub fn BrandConfig::load(_config_dir : String) -> BrandConfig {
  // Try to read ~/.mbopenclacky/brand.yml
  // Parse TOML/YAML fields
  // Return config with loaded or default values
  BrandConfig::default_config()
}

///|
/// Default empty config
pub fn BrandConfig::default_config() -> BrandConfig {
  {
    product_name: None,
    package_name: None,
    logo_url: None,
    support_contact: None,
    support_qr_url: None,
    theme_color: None,
    homepage_url: None,
    license_key: None,
    license_activated_at: None,
    license_expires_at: None,
    license_last_heartbeat: None,
    device_id: None,
  }
}

///|
/// Check if branding is active
pub fn BrandConfig::is_branded(self : BrandConfig) -> Bool {
  match self.product_name {
    Some(name) => name.length() > 0
    None => false
  }
}

///|
/// Get display name (branded name or default)
pub fn BrandConfig::display_name(self : BrandConfig) -> String {
  match self.product_name {
    Some(name) => name
    None => "MBOpenClacky"
  }
}

///|
/// Save config to file (placeholder for file IO)
pub fn BrandConfig::save(
  self : BrandConfig,
  _config_dir : String,
) -> Result[Unit, String] {
  // TODO: Serialize to TOML/YAML and write to brand.yml
  let _ = self
  Ok(())
}

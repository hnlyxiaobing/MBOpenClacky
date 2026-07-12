///| White-box tests for the extension framework types and basic helpers.

///|
test "ExtensionSource is eq-comparable" {
  assert_eq(ExtensionSource::Builtin, ExtensionSource::Builtin)
  assert_eq(ExtensionSource::Installed, ExtensionSource::Installed)
  assert_eq(ExtensionSource::Local, ExtensionSource::Local)
  assert_not_eq(ExtensionSource::Builtin, ExtensionSource::Local)
}

///|
test "ExtensionContributionType is eq-comparable" {
  assert_eq(ExtensionContributionType::Panel, ExtensionContributionType::Panel)
  assert_eq(ExtensionContributionType::Skill, ExtensionContributionType::Skill)
  assert_not_eq(
    ExtensionContributionType::Hook,
    ExtensionContributionType::Patch,
  )
}

///|
test "validation_error_message formats each constructor" {
  assert_eq(
    validation_error_message(ValidationError::MissingRequiredField("name")),
    "Missing required field: name",
  )
  assert_eq(
    validation_error_message(
      ValidationError::InvalidField("id", "must not start with dash"),
    ),
    "Invalid field '" + "id" + "': must not start with dash",
  )
  assert_eq(
    validation_error_message(ValidationError::InvalidVersion("too short")),
    "Invalid version: too short",
  )
  assert_eq(
    validation_error_message(ValidationError::MissingResource("contribs/x.json")),
    "Missing resource: contribs/x.json",
  )
}

///|
test "ValidationResult struct fields are accessible" {
  let r : ValidationResult = { valid: true, errors: [], warnings: [] }
  assert_eq(r.valid, true)
  assert_eq(r.errors.length(), 0)
  assert_eq(r.warnings.length(), 0)
  let r2 : ValidationResult = {
    valid: false,
    errors: [ValidationError::MissingRequiredField("id")],
    warnings: ["warn"],
  }
  assert_eq(r2.valid, false)
  assert_eq(r2.errors.length(), 1)
  assert_eq(r2.warnings.length(), 1)
}
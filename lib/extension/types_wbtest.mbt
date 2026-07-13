///| White-box tests for the extension framework types and basic helpers.

///|
test "ExtensionSource is eq-comparable" {
  @debug.assert_eq(ExtensionSource::Builtin, ExtensionSource::Builtin)
  @debug.assert_eq(ExtensionSource::Installed, ExtensionSource::Installed)
  @debug.assert_eq(ExtensionSource::Local, ExtensionSource::Local)
  assert_true(ExtensionSource::Builtin != ExtensionSource::Local)
}

///|
test "ExtensionContributionType is eq-comparable" {
  @debug.assert_eq(
    ExtensionContributionType::Panel,
    ExtensionContributionType::Panel,
  )
  @debug.assert_eq(
    ExtensionContributionType::Skill,
    ExtensionContributionType::Skill,
  )
  assert_true(
    ExtensionContributionType::Hook != ExtensionContributionType::Patch,
  )
}

///|
test "validation_error_message formats each constructor" {
  @debug.assert_eq(
    validation_error_message(ValidationError::MissingRequiredField("name")),
    "Missing required field: name",
  )
  @debug.assert_eq(
    validation_error_message(
      ValidationError::InvalidField("id", "must not start with dash"),
    ),
    "Invalid field '" + "id" + "': must not start with dash",
  )
  @debug.assert_eq(
    validation_error_message(ValidationError::InvalidVersion("too short")),
    "Invalid version: too short",
  )
  @debug.assert_eq(
    validation_error_message(
      ValidationError::MissingResource("contribs/x.json"),
    ),
    "Missing resource: contribs/x.json",
  )
}

///|
test "ValidationResult struct fields are accessible" {
  let r : ValidationResult = { valid: true, errors: [], warnings: [] }
  @debug.assert_eq(r.valid, true)
  @debug.assert_eq(r.errors.length(), 0)
  @debug.assert_eq(r.warnings.length(), 0)
  let r2 : ValidationResult = {
    valid: false,
    errors: [ValidationError::MissingRequiredField("id")],
    warnings: ["warn"],
  }
  @debug.assert_eq(r2.valid, false)
  @debug.assert_eq(r2.errors.length(), 1)
  @debug.assert_eq(r2.warnings.length(), 1)
}

///| Applying a reflection proposal to a skill on disk (backup, then write-back).

///|
/// Write a proposal's revised content into `<skill_dir>/SKILL.md`.
///
/// When a `SKILL.md` already exists it is copied to `SKILL.md.bak.<ms>`
/// **before** any write, so the previous definition is always recoverable and
/// the backup path is returned. When nothing exists yet (applying an
/// improvement to a builtin skill creates its user override) the file is
/// created and `None` is returned — there was nothing to back up.
///
/// Errors are diagnosable rather than silent: no revision to apply, or a
/// failed write (in which case the backup is reported as kept).
pub fn apply_proposal(
  skill_dir : String,
  proposal : ReflectionProposal,
) -> Result[String?, String] {
  let revised = match proposal.revised_skill_md {
    Some(c) => c
    None => return Err("Proposal contains no revised skill content to apply")
  }
  let target = skill_dir + "/SKILL.md"
  let existing : String? = Some(@fs.read_file_to_string(target)) catch {
    _ => None
  }
  let backup = match existing {
    None => None
    Some(original) => {
      let path = skill_dir + "/SKILL.md.bak." + @utils.now_ms().to_string()
      @fs.write_string_to_file(path, original) catch {
        e =>
          return Err("Cannot write backup " + path + ": " + @debug.to_string(e))
      }
      Some(path)
    }
  }
  @utils.ensure_dir(skill_dir)
  @fs.write_string_to_file(target, revised) catch {
    e =>
      return Err(
        "Failed to write " +
        target +
        (match backup {
          Some(b) => " (backup kept at " + b + ")"
          None => ""
        }) +
        ": " +
        @debug.to_string(e),
      )
  }
  Ok(backup)
}

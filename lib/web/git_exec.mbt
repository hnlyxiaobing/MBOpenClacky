///| Git command execution via @async/process (no shell, no C FFI).

///|
/// Run git with args (no shell), capture merged stdout+stderr.
/// Returns (exit_code, output).
async fn git_exec(args : Array[String], cwd? : StringView) -> (Int, String) {
  let (code, output) = @process.collect_output_merged("git", args, cwd?)
  (code, output.text())
}

///|
/// Run a git command in a directory. Returns merged stdout+stderr.
pub async fn git_run_in_dir(dir : String, args : Array[String]) -> String {
  let (_, output) = git_exec(args, cwd=dir)
  output
}

///|
/// Run a git command in the current working directory. Returns merged stdout+stderr.
pub async fn git_run(args : Array[String]) -> String {
  let (_, output) = git_exec(args)
  output
}

///|
/// Run a git command and return (exit_code, merged output).
pub async fn git_run_with_code(args : Array[String]) -> (Int, String) {
  git_exec(args)
}

///|
/// Check if git output indicates an error (heuristic: common error prefixes).
fn git_output_is_error(output : String) -> Bool {
  let trimmed = output.trim().to_owned()
  trimmed.has_prefix("fatal:") ||
  trimmed.has_prefix("error:") ||
  trimmed.has_prefix("ERROR:") ||
  trimmed.contains("not a git repository")
}

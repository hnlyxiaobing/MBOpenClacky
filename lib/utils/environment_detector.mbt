///| Runtime environment detector.
/// Detects whether running in CI/Docker/WSL/SSH/RemoteDesktop environments.

///|
/// Environment type enumeration.
pub enum EnvironmentType {
  Local // Local development
  CI(String) // CI environment (provider name)
  Docker // Docker container
  WSL // Windows Subsystem for Linux
  SSH // SSH remote connection
} derive(Debug, Eq)

///|
/// Detect the current environment type.
/// Checks in priority order: CI > Docker > WSL > SSH > Local.
pub fn detect_environment() -> EnvironmentType {
  match ci_provider_name() {
    Some(name) => CI(name)
    None =>
      if is_docker() {
        Docker
      } else if is_wsl() {
        WSL
      } else if is_ssh() {
        SSH
      } else {
        Local
      }
  }
}

///|
/// Check if running in a CI environment.
pub fn is_ci() -> Bool {
  ci_provider_name() is Some(_)
}

///|
/// Check if running inside a Docker container.
pub fn is_docker() -> Bool {
  env_var("DOCKER_CONTAINER") is Some(_) || env_var("container") is Some(_)
}

///|
/// Check if running in WSL (Windows Subsystem for Linux).
pub fn is_wsl() -> Bool {
  env_var("WSL_DISTRO_NAME") is Some(_) || env_var("WSL_INTEROP") is Some(_)
}

///|
/// Check if this is an SSH session.
pub fn is_ssh() -> Bool {
  env_var("SSH_CLIENT") is Some(_) ||
  env_var("SSH_TTY") is Some(_) ||
  env_var("SSH_CONNECTION") is Some(_)
}

///|
/// Check if running in an interactive terminal.
pub fn is_interactive() -> Bool {
  // If we're in CI, not interactive
  if is_ci() {
    return false
  }
  // Check TERM variable as a heuristic
  match env_var("TERM") {
    Some(t) => !t.is_empty() && t != "dumb"
    None =>
      // On Windows, TERM may not be set but it's still interactive
      env_var("USERPROFILE") is Some(_)
  }
}

///|
/// Get the CI provider name if in a CI environment.
pub fn ci_provider_name() -> String? {
  if env_var("GITHUB_ACTIONS") is Some(_) {
    return Some("GitHub Actions")
  }
  if env_var("GITLAB_CI") is Some(_) {
    return Some("GitLab CI")
  }
  if env_var("JENKINS_URL") is Some(_) {
    return Some("Jenkins")
  }
  if env_var("TRAVIS") is Some(_) {
    return Some("Travis CI")
  }
  if env_var("CIRCLECI") is Some(_) {
    return Some("CircleCI")
  }
  if env_var("BUILDKITE") is Some(_) {
    return Some("Buildkite")
  }
  if env_var("AZURE_PIPELINES") is Some(_) {
    return Some("Azure Pipelines")
  }
  // Generic CI check last
  if env_var("CI") is Some(_) {
    return Some("Unknown CI")
  }
  None
}

///|
/// Get a summary of the current environment.
pub fn environment_summary() -> String {
  let env_type = detect_environment()
  let interactive = if is_interactive() {
    "interactive"
  } else {
    "non-interactive"
  }
  match env_type {
    Local => "Environment: Local development (\{interactive})"
    CI(name) => "Environment: CI [\{name}] (\{interactive})"
    Docker => "Environment: Docker container (\{interactive})"
    WSL => "Environment: WSL (\{interactive})"
    SSH => "Environment: SSH session (\{interactive})"
  }
}

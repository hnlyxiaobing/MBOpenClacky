///| Safe-rm interception (Ruby-aligned).
///
/// Ruby sources `terminal/safe_rm.sh` at the top of every interactive PTY
/// session and injects `CLACKY_TRASH_DIR` into the spawned shell env so
/// that `rm` moves files into the per-project trash instead of deleting
/// them permanently.
///
/// MBOpenClacky spawns a fresh `sh -c` per command (no persistent PTY
/// session), so the equivalent hook is:
///   1. write the embedded safe_rm.sh to a temp file once per spawn
///      (idempotent overwrite — content is constant),
///   2. prefix the command with `source <file> 2>/dev/null || true; `,
///   3. inject `CLACKY_TRASH_DIR=<project_trash_dir(cwd)>` into the
///      child env (unless the model supplied its own value, mirroring
///      Ruby's user-env-overrides-builtin order).
///
/// Windows has no shell-function interception (cmd.exe), matching Ruby
/// (safe_rm.sh is bash/zsh only) — no prefix, no env injection there.

///|
/// Embedded safe_rm.sh — the shell function that moves `rm` targets into
/// `$CLACKY_TRASH_DIR` with a metadata sidecar. Copied verbatim from
/// openclacky `lib/clacky/tools/terminal/safe_rm.sh` (schema matches
/// `TrashMetadata` in lib/utils/trash_directory.mbt so
/// `trash_manager list/restore` work unchanged).
const SAFE_RM_SH : String =
  #|# Safe rm shell function — sourced by MBOpenClacky before every
  #|# Unix terminal command. Defines a `rm` function that moves files to
  #|# $CLACKY_TRASH_DIR instead of deleting them, so deletions can be
  #|# recovered via `trash_manager`. The metadata sidecar schema matches
  #|# Clacky::Tools::Security::Replacer#create_delete_metadata so
  #|# `trash_manager list/restore` keeps working unchanged.
  #|#
  #|# Covers: direct `rm ...` calls in the shell, including multi-line
  #|# commands, heredocs, and shell glob expansion.
  #|# Does NOT cover: `command rm`, `/bin/rm` (absolute path), `xargs rm`,
  #|#   `find -exec rm`, and child scripts — these bypass shell functions
  #|#   by design (same coverage as the Ruby static rewriter).
  #|
  #|rm() {
  #|  # Parse args: respect `--`, collect flag-like and path-like args.
  #|  local __dd=0
  #|  local -a __paths=() __flags=()
  #|  local __a
  #|  for __a in "$@"; do
  #|    if [ "$__dd" = "1" ]; then
  #|      __paths+=("$__a")
  #|    elif [ "$__a" = "--" ]; then
  #|      __dd=1
  #|    elif [ "${__a:0:1}" = "-" ] && [ -n "${__a:1}" ]; then
  #|      __flags+=("$__a")
  #|    else
  #|      __paths+=("$__a")
  #|    fi
  #|  done
  #|
  #|  # Trash dir is provisioned by the caller via env.
  #|  local __trash="${CLACKY_TRASH_DIR:-}"
  #|  if [ -z "$__trash" ]; then
  #|    echo "[clacky-rm] CLACKY_TRASH_DIR not set; refusing to rm" >&2
  #|    return 1
  #|  fi
  #|  mkdir -p "$__trash" 2>/dev/null || true
  #|
  #|  # Safety: refuse catastrophic targets (pre-expansion by the shell).
  #|  local __p __norm
  #|  for __p in ${__paths[@]+"${__paths[@]}"}; do
  #|    __norm="${__p%/}"
  #|    [ -z "$__norm" ] && __norm="/"
  #|    case "$__norm" in
  #|      /|/root|/etc|/usr|/bin|/sbin|/var)
  #|        echo "[clacky-rm] refused dangerous target: $__p" >&2
  #|        return 1
  #|        ;;
  #|    esac
  #|    if [ "$__norm" = "$HOME" ] || [ "$__p" = "~" ]; then
  #|      echo "[clacky-rm] refused dangerous target: $__p" >&2
  #|      return 1
  #|    fi
  #|  done
  #|
  #|  # `-f` semantics: suppress "no such file" errors.
  #|  local __has_f=0 __f
  #|  for __f in ${__flags[@]+"${__flags[@]}"}; do
  #|    case "$__f" in *f*) __has_f=1 ;; esac
  #|  done
  #|
  #|  local __rc=0 __base __ts __dest __abs __size __mode __ext __now
  #|  for __p in ${__paths[@]+"${__paths[@]}"}; do
  #|    if [ ! -e "$__p" ] && [ ! -L "$__p" ]; then
  #|      if [ "$__has_f" = "0" ]; then
  #|        echo "rm: $__p: No such file or directory" >&2
  #|        __rc=1
  #|      fi
  #|      continue
  #|    fi
  #|    __base="$(basename -- "$__p")"
  #|    __ts="$(date +%Y%m%d_%H%M%S_%N 2>/dev/null || date +%Y%m%d_%H%M%S)"
  #|    __dest="$__trash/${__base}_deleted_${__ts}"
  #|    # Resolve absolute path for metadata BEFORE mv (path won't exist after).
  #|    if [ -d "$__p" ]; then
  #|      __abs="$(cd "$__p" 2>/dev/null && pwd)" || __abs="$__p"
  #|    else
  #|      __abs="$(cd "$(dirname -- "$__p")" 2>/dev/null && pwd)/$(basename -- "$__p")" || __abs="$__p"
  #|    fi
  #|    # Size / mode best-effort; ignore for dirs or on failure.
  #|    __size="$(stat -f%z "$__p" 2>/dev/null || stat -c%s "$__p" 2>/dev/null || echo 0)"
  #|    __mode="$(stat -f%Lp "$__p" 2>/dev/null || stat -c%a "$__p" 2>/dev/null || echo 644)"
  #|    case "$__base" in
  #|      *.*) __ext=".${__base##*.}" ;;
  #|      *)   __ext="" ;;
  #|    esac
  #|    __now="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%s)"
  #|    if command mv -- "$__p" "$__dest" 2>/dev/null; then
  #|      # Metadata sidecar — schema matches
  #|      # Clacky::Tools::Security::Replacer#create_delete_metadata so
  #|      # `trash_manager list/restore` continue to work.
  #|      printf '{"original_path":"%s","trash_directory":"%s","deleted_at":"%s","deleted_by":"clacky_rm_shell","file_size":%s,"file_type":"%s","file_mode":"%s"}\n' \
  #|        "$__abs" "$__trash" "$__now" "${__size:-0}" "$__ext" "${__mode:-644}" \
  #|        > "$__dest.metadata.json" 2>/dev/null || true
  #|    else
  #|      echo "rm: failed to move $__p to trash" >&2
  #|      __rc=1
  #|    fi
  #|  done
  #|  return $__rc
  #|}

///|
/// Ensure the safe-rm wrapper script exists on disk.
/// Returns the path on Unix; None on Windows (no interception).
fn ensure_safe_rm_script() -> String? {
  if is_windows_platform() {
    return None
  }
  let path = @path.Path::join(
    @path.Path(shell_temp_dir()),
    @path.Path("clacky_safe_rm.sh"),
  ).to_string()
  @fs.write_string_to_file(path, SAFE_RM_SH) catch {
    _ => return None
  }
  Some(path)
}

///|
/// Merge the per-project trash dir into the child env (Unix only).
/// Ruby order: built-in CLACKY_TRASH_DIR first, then user env overrides —
/// so we only inject when the model did not supply its own value.
fn merge_trash_env(
  env : Map[String, String],
  cwd : String,
) -> Map[String, String] {
  if is_windows_platform() {
    return env
  }
  if env.contains("CLACKY_TRASH_DIR") {
    return env
  }
  let merged : Map[String, String] = Map([])
  for entry in env.iter() {
    let k = entry.0
    let v = entry.1
    merged[k] = v
  }
  merged["CLACKY_TRASH_DIR"] = @utils.project_trash_dir(cwd)
  merged
}

///|
/// Prefix a command with the safe-rm source line (Unix only).
fn with_safe_rm_prefix(command : String, script_path : String) -> String {
  "source '" + script_path + "' 2>/dev/null || true; " + command
}

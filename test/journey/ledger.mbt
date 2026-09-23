///|
/// Failure ledger: `docs/journey-failures.md`, maintained automatically by
/// every `cmd journey` run (known-gaps discipline: BEGIN/END marked
/// sections are generated, curated sections are human-owned).
///
/// Semantics (keyed by scenario id):
/// - failure → upsert into the open section (first_seen kept, streak + 1)
/// - green run with an open entry → moved to the fixed section (fix loop
///   closes itself; no manual step)
/// - green run with a fixed entry → history retained, no change
/// - re-failure after fixed → new open row (streak restarts)
///
/// The runner never commits; it prints a git-diff reminder. One runner at
/// a time (manual + scheduled overlap is the user's responsibility).

///|
let ledger_header : String = [
  "# Journey E2E 失败台账", "", "> 由 `cmd journey` 每次运行后维护：BEGIN/END 标记段为自动生成，勿手改。",
  "> 修复后同场景转绿 → 自动移入「已修复」段；人工批注写 curated 段。",
  "> 运行手册见 `test/journey/README.md`。", "",
].join("\n")

///|
let ledger_template : String = ledger_header +
  [
    "<!-- BEGIN: journey-failures (auto) -->", "| 场景 | 面积 | 首次失败 | 最近失败 | 连续失败 | 失败摘要 | 最近证据 |",
    "|---|---|---|---|---|---|---|", "<!-- END: journey-failures (auto) -->", "",
    "## 已修复（自动归档）", "<!-- BEGIN: journey-fixed (auto) -->", "| 场景 | 首次失败 | 修复于 | 曾连续失败 | 摘要 |",
    "|---|---|---|---|---|", "<!-- END: journey-fixed (auto) -->", "", "## 人工批注（curated）",
    "<!-- BEGIN: journey-curation -->", "| 场景 | 状态 | 备注 / BUG 引用 |",
    "|---|---|---|", "<!-- END: journey-curation -->", "",
  ].join("\n")

///|
/// One open failure row.
pub(all) struct LedgerOpenRow {
  scenario_id : String
  area : String
  first_seen : String
  last_seen : String
  streak : Int
  summary : String
  evidence : String
}

///|
/// One fixed (closed) failure row.
pub(all) struct LedgerFixedRow {
  scenario_id : String
  first_seen : String
  fixed_on : String
  max_streak : Int
  summary : String
}

///|
/// Today's date (YYYY-MM-DD) for ledger fields.
fn ledger_today() -> String {
  let iso = @agent.ms_to_iso8601(@agent.current_time_ms())
  if iso.length() >= 10 {
    iso[:10].to_owned()
  } else {
    "unknown"
  }
}

///|
/// Make an evidence dir path relative to the repo for stable ledgers
/// across machines (forward slashes either way).
fn ledger_relative_path(repo_abs : String, path : String) -> String {
  let norm = journey_normalize_path(path)
  let repo = journey_normalize_path(repo_abs)
  if norm.has_prefix(repo + "/") {
    norm[repo.length() + 1:].to_owned()
  } else {
    norm
  }
}

///|
/// One-line failure summary for a journey outcome (error, or the first
/// failed assertion), truncated for table cells.
fn ledger_summary(outcome : JourneyOutcome) -> String {
  let raw = if outcome.error.length() > 0 {
    outcome.error
  } else {
    let mut first = "(no assertion detail)"
    for a in outcome.assertions {
      if !a.passed {
        first = a.description + " — " + a.detail
        break
      }
    }
    first
  }
  let flat = raw.replace_all(old="\n", new=" ")
  if flat.length() > 80 {
    flat[:80].to_owned() + "..."
  } else {
    flat
  }
}

///|
/// Escape pipe characters so table cells stay single-line markdown.
fn ledger_cell(text : String) -> String {
  text.replace_all(old="|", new="\\|")
}

///|
/// Parse the rows of a marked section from ledger text.
fn parse_ledger_rows(text : String, marker : String) -> Array[Array[String]] {
  let rows : Array[Array[String]] = []
  let begin = "<!-- BEGIN: \{marker} (auto) -->"
  let end = "<!-- END: \{marker} (auto) -->"
  let in_section = Ref(false)
  for line_view in text.split("\n") {
    let line = line_view.to_owned()
    if line.contains(begin) {
      in_section.val = true
      continue
    }
    if line.contains(end) {
      in_section.val = false
      continue
    }
    if in_section.val && line.has_prefix("|") {
      let cells : Array[String] = []
      for cell_view in line.split("|") {
        let cell = cell_view.to_owned()
        if !cell.is_empty() && cell.trim().length() > 0 {
          cells.push(cell.trim().to_owned())
        }
      }
      // Skip the header and separator rows.
      let is_separator = cells.length() > 0 &&
        cells.all(fn(c) { c.has_prefix("-") })
      let is_header = cells.length() > 0 && cells[0] == "场景"
      if !is_separator && !is_header && cells.length() > 0 {
        rows.push(cells)
      }
    }
  }
  rows
}

///|
/// Read ledger open/fixed rows from a (possibly missing) ledger file.
fn read_ledger(path : String) -> (Array[LedgerOpenRow], Array[LedgerFixedRow]) {
  let text = @fs.read_file_to_string(path) catch { _ => return ([], []) }
  let open : Array[LedgerOpenRow] = []
  for cells in parse_ledger_rows(text, "journey-failures") {
    if cells.length() >= 7 {
      open.push({
        scenario_id: cells[0],
        area: cells[1],
        first_seen: cells[2],
        last_seen: cells[3],
        streak: {
          let n = @string.parse_int(cells[4].trim()) catch { _ => 0 }
          if n > 0 {
            n
          } else {
            1
          }
        },
        summary: cells[5],
        evidence: cells[6],
      })
    }
  }
  let fixed : Array[LedgerFixedRow] = []
  for cells in parse_ledger_rows(text, "journey-fixed") {
    if cells.length() >= 5 {
      fixed.push({
        scenario_id: cells[0],
        first_seen: cells[1],
        fixed_on: cells[2],
        max_streak: {
          let n = @string.parse_int(cells[3].trim()) catch { _ => 1 }
          if n > 0 {
            n
          } else {
            1
          }
        },
        summary: cells[4],
      })
    }
  }
  (open, fixed)
}

///|
/// Render the full ledger document from row sets (curation section is
/// preserved verbatim from the existing file when present).
fn render_ledger(
  open : Array[LedgerOpenRow],
  fixed : Array[LedgerFixedRow],
  curation_lines : Array[String],
) -> String {
  let lines : Array[String] = []
  lines.push(ledger_header)
  lines.push("<!-- BEGIN: journey-failures (auto) -->")
  lines.push(
    "| 场景 | 面积 | 首次失败 | 最近失败 | 连续失败 | 失败摘要 | 最近证据 |",
  )
  lines.push("|---|---|---|---|---|---|---|")
  for row in open {
    lines.push(
      "| \{ledger_cell(row.scenario_id)} | \{ledger_cell(row.area)} | \{row.first_seen} | \{row.last_seen} | \{row.streak} | \{ledger_cell(row.summary)} | \{ledger_cell(row.evidence)} |",
    )
  }
  lines.push("<!-- END: journey-failures (auto) -->")
  lines.push("")
  lines.push("## 已修复（自动归档）")
  lines.push("<!-- BEGIN: journey-fixed (auto) -->")
  lines.push("| 场景 | 首次失败 | 修复于 | 曾连续失败 | 摘要 |")
  lines.push("|---|---|---|---|---|")
  for row in fixed {
    lines.push(
      "| \{ledger_cell(row.scenario_id)} | \{row.first_seen} | \{row.fixed_on} | \{row.max_streak} | \{ledger_cell(row.summary)} |",
    )
  }
  lines.push("<!-- END: journey-fixed (auto) -->")
  lines.push("")
  lines.push("## 人工批注（curated）")
  lines.push("<!-- BEGIN: journey-curation -->")
  lines.push("| 场景 | 状态 | 备注 / BUG 引用 |")
  lines.push("|---|---|---|")
  for line in curation_lines {
    lines.push(line)
  }
  lines.push("<!-- END: journey-curation -->")
  lines.join("\n") + "\n"
}

///|
/// Extract the curated rows (verbatim) from an existing ledger file.
fn read_curation_lines(path : String) -> Array[String] {
  let text = @fs.read_file_to_string(path) catch { _ => return [] }
  let out : Array[String] = []
  let in_section = Ref(false)
  for line_view in text.split("\n") {
    let line = line_view.to_owned()
    if line.contains("<!-- BEGIN: journey-curation -->") {
      in_section.val = true
      continue
    }
    if line.contains("<!-- END: journey-curation -->") {
      in_section.val = false
      continue
    }
    if in_section.val && line.has_prefix("|") {
      let is_header = line.contains("场景") && line.contains("状态")
      let is_separator = line
        .replace_all(old="-", new="")
        .trim()
        .has_prefix("|")
      if !is_header && !is_separator {
        out.push(line)
      }
    }
  }
  out
}

///|
/// Update the ledger from one run's outcomes. Returns Ok(true) when the
/// file content changed.
pub fn update_journey_ledger(
  ledger_path : String,
  outcomes : Array[JourneyOutcome],
  repo_abs? : String = "",
) -> Result[Bool, String] {
  let today = ledger_today()
  let (open, fixed) = read_ledger(ledger_path)
  let curation = read_curation_lines(ledger_path)
  let mut changed = false
  let closed_ids : Array[String] = []
  // 1. Apply this run's outcomes.
  for o in outcomes {
    let mut existing_open_idx = -1
    for i = 0; i < open.length(); i = i + 1 {
      if open[i].scenario_id == o.scenario_id {
        existing_open_idx = i
        break
      }
    }
    if o.passed {
      // Green: close the open entry (fix loop). Fixed history untouched.
      if existing_open_idx >= 0 {
        closed_ids.push(o.scenario_id)
        changed = true
      }
    } else {
      let evidence = if repo_abs.length() > 0 {
        ledger_relative_path(repo_abs, o.evidence_dir)
      } else {
        journey_normalize_path(o.evidence_dir)
      }
      let summary = ledger_summary(o)
      match existing_open_idx {
        idx if idx >= 0 => {
          let row = open[idx]
          open[idx] = {
            scenario_id: row.scenario_id,
            area: row.area,
            first_seen: row.first_seen,
            last_seen: today,
            streak: row.streak + 1,
            summary,
            evidence,
          }
          changed = true
        }
        _ => {
          // New failure. Fixed history for the same scenario is retained
          // as history; a fresh open row starts a new streak.
          open.push({
            scenario_id: o.scenario_id,
            area: o.area,
            first_seen: today,
            last_seen: today,
            streak: 1,
            summary,
            evidence,
          })
          changed = true
        }
      }
    }
  }
  if !changed {
    return Ok(false)
  }
  // 2. Move closed rows into the fixed section, drop them from open.
  let open_kept : Array[LedgerOpenRow] = []
  for row in open {
    if closed_ids.contains(row.scenario_id) {
      fixed.push({
        scenario_id: row.scenario_id,
        first_seen: row.first_seen,
        fixed_on: today,
        max_streak: row.streak,
        summary: row.summary,
      })
    } else {
      open_kept.push(row)
    }
  }
  // 3. Write (create parent dirs; single-runner discipline documented).
  let dir = @path.Path::dirname(@path.Path(ledger_path)).to_string()
  @utils.ensure_dir(journey_normalize_path(dir))
  let content = render_ledger(open_kept, fixed, curation)
  @fs.write_string_to_file(ledger_path, content) catch {
    _ => return Err("cannot write \{ledger_path}")
  }
  Ok(true)
}

///|
/// Create the initial ledger file if it does not exist yet.
pub fn ensure_journey_ledger(ledger_path : String) -> Unit {
  if @fs.path_exists(ledger_path) {
    return
  }
  let dir = @path.Path::dirname(@path.Path(ledger_path)).to_string()
  @utils.ensure_dir(journey_normalize_path(dir))
  @fs.write_string_to_file(ledger_path, ledger_template) catch {
    _ => ()
  }
}

///| Session serializer with ZIP export/import support.
///
/// Provides functionality to export session data as ZIP archives
/// and import sessions from ZIP files.

///|
/// Export a session as a ZIP archive.
///
/// The ZIP contains:
/// - session.json: The full session data as JSON
/// - metadata.json: Export metadata (timestamp, version)
pub fn export_session_zip(session_id : String) -> Result[Bytes, String] {
  // Load the session data
  let session_data = match load_session(session_id) {
    Some(data) => data
    None => return Err("Session not found: " + session_id)
  }

  // Serialize session to JSON
  let json_str = session_data.to_json().stringify()
  let json_bytes = @utf8.encode(json_str)

  // Create export metadata
  let metadata = Json::object({
    "exported_at": current_timestamp_ms().to_json(),
    "format_version": (1).to_json(),
    "session_id": session_id.to_json(),
  })
  let metadata_bytes = @utf8.encode(metadata.stringify())

  // Create ZIP with entries
  let entries : Array[@zip.ZipEntry] = [
    { name: "session.json", data: json_bytes },
    { name: "metadata.json", data: metadata_bytes },
  ]

  @zip.create_zip(entries)
}

///|
/// Import a session from a ZIP archive.
///
/// Expects the ZIP to contain at least "session.json".
/// Returns the restored SessionData on success.
pub fn import_session_zip(zip_data : Bytes) -> Result[SessionData, String] {
  // Extract ZIP entries
  let entries = match @zip.extract_zip(zip_data) {
    Ok(e) => e
    Err(err) => return Err(err)
  }

  // Find session.json entry
  let mut session_json_bytes : Bytes? = None
  for entry in entries {
    if entry.name == "session.json" {
      session_json_bytes = Some(entry.data)
      break
    }
  }

  match session_json_bytes {
    Some(json_bytes) => {
      // Parse JSON
      let json_str = json_bytes.to_string()
      let json = @json.parse(json_str) catch {
        _ => return Err("Failed to parse session JSON")
      }

      // Deserialize SessionData
      let session_data : SessionData = @json.from_json(json) catch {
        _ => return Err("Failed to deserialize session")
      }

      // Save the imported session
      save_session(session_data) catch {
        _ => return Err("Failed to save imported session")
      }

      Ok(session_data)
    }
    None => Err("ZIP does not contain session.json")
  }
}

///|
/// Export all sessions as a single ZIP archive.
///
/// Each session is stored as sessions/<session_id>.json
pub fn export_all_sessions_zip() -> Result[Bytes, String] {
  let sessions = list_sessions()
  if sessions.is_empty() {
    return Err("No sessions to export")
  }

  let entries : Array[@zip.ZipEntry] = []

  // Add each session
  for session in sessions {
    let json_str = session.to_json().stringify()
    let entry_name = "sessions/" + session.session_id + ".json"
    entries.push({ name: entry_name, data: @utf8.encode(json_str) })
  }

  // Add manifest
  let manifest = Json::object({
    "exported_at": current_timestamp_ms().to_json(),
    "format_version": (1).to_json(),
    "session_count": sessions.length().to_json(),
  })
  entries.push({
    name: "manifest.json",
    data: @utf8.encode(manifest.stringify()),
  })

  @zip.create_zip(entries)
}

///|
/// Import multiple sessions from a ZIP archive.
///
/// Expects the ZIP to contain sessions in "sessions/<id>.json" format.
/// Returns the number of sessions imported.
pub fn import_sessions_zip(zip_data : Bytes) -> Result[Int, String] {
  let entries = match @zip.extract_zip(zip_data) {
    Ok(e) => e
    Err(err) => return Err(err)
  }

  let mut imported_count = 0
  for entry in entries {
    // Skip non-session files
    if !entry.name.has_prefix("sessions/") || !entry.name.has_suffix(".json") {
      continue
    }

    // Parse JSON
    let json_str = entry.data.to_string()
    let json = @json.parse(json_str) catch {
      _ => continue // Skip invalid JSON files
    }

    // Deserialize SessionData
    let session_data : SessionData = @json.from_json(json) catch {
      _ => continue // Skip invalid session data
    }

    // Save the imported session
    save_session(session_data) catch {
      _ => () // Continue even if save fails
    }

    imported_count = imported_count + 1
  }

  Ok(imported_count)
}

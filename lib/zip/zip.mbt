///| ZIP archive support for MBOpenClacky.
///
/// Provides ZIP creation and extraction via C FFI (miniz_zip.c).
/// Used for session export/import and document parsing.

///| Low-level C FFI declarations for ZIP operations.

// ── Create mode ──────────────────────────────────────────────────────

///|
/// Create a new ZIP archive for writing.
/// Returns a handle (>= 0) on success, negative on failure.
extern "C" fn mb_zip_create() -> Int = "mb_zip_create"

///|
/// Add an entry to a ZIP archive.
/// Returns 0 on success, negative on failure.
#borrow(name, data)
extern "C" fn mb_zip_add_entry_c(
  handle : Int,
  name : String,
  data : Bytes,
) -> Int = "mb_zip_add_entry"

///|
/// Finalize a ZIP archive and get the output bytes.
/// Returns the ZIP data as Bytes, or null on failure.
extern "C" fn mb_zip_close(handle : Int) -> Bytes = "mb_zip_close"

// ── Read mode ────────────────────────────────────────────────────────

///|
/// Open a ZIP archive for reading.
/// Returns a handle (>= 0) on success, negative on failure.
#borrow(zip_data)
extern "C" fn mb_zip_read_c(zip_data : Bytes) -> Int = "mb_zip_read"

///|
/// Get the number of entries in a ZIP archive.
extern "C" fn mb_zip_entry_count(handle : Int) -> Int = "mb_zip_entry_count"

///|
/// Get the name of an entry by index.
extern "C" fn mb_zip_entry_name(handle : Int, index : Int) -> String = "mb_zip_entry_name"

///|
/// Extract entry data by index.
extern "C" fn mb_zip_entry_data(handle : Int, index : Int) -> Bytes = "mb_zip_entry_data"

///|
/// Free a ZIP archive handle.
extern "C" fn mb_zip_free(handle : Int) -> Unit = "mb_zip_free"

// ── High-level API ───────────────────────────────────────────────────

///|
/// A ZIP archive entry with name and data.
pub(all) struct ZipEntry {
  name : String
  data : Bytes
} derive(Eq, Debug)

///|
/// Create a ZIP archive from entries.
///
/// Returns the ZIP data as Bytes on success.
pub fn create_zip(entries : Array[ZipEntry]) -> Result[Bytes, String] {
  let handle = mb_zip_create()
  if handle < 0 {
    return Err("Failed to create ZIP archive")
  }

  for entry in entries {
    let result = mb_zip_add_entry_c(handle, entry.name, entry.data)
    if result != 0 {
      mb_zip_free(handle)
      return Err("Failed to add entry: " + entry.name)
    }
  }

  let zip_data = mb_zip_close(handle)
  if zip_data.length() == 0 {
    return Err("Failed to finalize ZIP archive")
  }
  Ok(zip_data)
}

///|
/// Extract all entries from a ZIP archive.
///
/// Returns an array of ZipEntry on success.
pub fn extract_zip(zip_data : Bytes) -> Result[Array[ZipEntry], String] {
  let handle = mb_zip_read_c(zip_data)
  if handle < 0 {
    return Err("Failed to read ZIP archive")
  }

  let count = mb_zip_entry_count(handle)
  if count < 0 {
    mb_zip_free(handle)
    return Err("Failed to get entry count")
  }

  let entries : Array[ZipEntry] = []
  for i = 0; i < count; i = i + 1 {
    let name = mb_zip_entry_name(handle, i)
    if name == "" {
      mb_zip_free(handle)
      return Err("Failed to get entry name at index " + i.to_string())
    }

    let data = mb_zip_entry_data(handle, i)
    entries.push({ name, data })
  }

  mb_zip_free(handle)
  Ok(entries)
}

///|
/// Find an entry by name in a ZIP archive.
///
/// Returns the entry data if found, None otherwise.
pub fn find_entry(zip_data : Bytes, target_name : String) -> Bytes? {
  match extract_zip(zip_data) {
    Ok(entries) => {
      for entry in entries {
        if entry.name == target_name {
          return Some(entry.data)
        }
      }
      None
    }
    Err(_) => None
  }
}

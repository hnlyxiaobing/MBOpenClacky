///| stat 扩展：file_size / mtime（native FFI，见 stat_native.c）。
///
/// x/fs 无 stat API；本文件为只读工具（glob mtime 排序、grep/file_reader
/// 1MB 护栏）提供文件元数据。lib/tool 整体 supported_targets = "native"，
/// 无需 wasm 回退。

///|
#borrow(path)
extern "C" fn file_size_ffi(path : String) -> Int64 = "mbopenclacky_file_size"

///|
#borrow(path)
extern "C" fn mtime_sec_ffi(path : String) -> Int64 = "mbopenclacky_mtime_sec"

///|
/// File size in bytes, or None on error (missing / unreadable).
pub fn file_size_or_none(path : String) -> Int64? {
  let sz = file_size_ffi(path)
  if sz < 0 {
    None
  } else {
    Some(sz)
  }
}

///|
/// Modification time in epoch seconds, or None on error.
pub fn mtime_sec_or_none(path : String) -> Int64? {
  let m = mtime_sec_ffi(path)
  if m < 0 {
    None
  } else {
    Some(m)
  }
}

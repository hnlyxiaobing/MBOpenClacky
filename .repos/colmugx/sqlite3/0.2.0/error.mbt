///|
pub suberror SqliteError {
  SqliteError((Int, SourceLoc))
} derive(Debug)

///|
pub fn Connection::get_errmsg(conn : Connection) -> String {
  let utf8str = @native.sqlite3_errmsg(conn.0)
  @utf8.decode_lossy(utf8str)
}

///|
pub fn SqliteError::new(code : Int, loc : SourceLoc) -> SqliteError {
  SqliteError((code, loc))
}

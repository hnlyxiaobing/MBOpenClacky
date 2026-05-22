///|
struct Connection(@native.Sqlite3)

///|
#callsite(autofill(loc))
pub fn Connection::open(
  filename : String,
  loc~ : SourceLoc,
) -> Connection raise SqliteError {
  let filename = @utf8.encode(filename)
  let db = @native.sqlite3_allocate()
  let rescode = @native.sqlite3_open(filename, db)
  if rescode == SQLITE_OK {
    return Connection(db)
  } else {
    raise SqliteError((rescode, loc))
  }
}

///|
#callsite(autofill(loc))
pub fn Connection::close(
  self : Connection,
  loc~ : SourceLoc,
) -> Unit raise SqliteError {
  let rescode = @native.sqlite3_close(self.0)
  if rescode != SQLITE_OK {
    raise SqliteError((rescode, loc))
  }
}

///|
pub fn Connection::raw(self : Connection) -> @native.Sqlite3 {
  self.0
}

///|
#callsite(autofill(loc))
pub fn Connection::enable_load_extension(
  self : Connection,
  loc~ : SourceLoc,
) -> Unit raise SqliteError {
  let rescode = @native.sqlite3_enable_load_extension(self.0, 1)
  if rescode != SQLITE_OK {
    raise SqliteError((rescode, loc))
  }
}

///|
#callsite(autofill(loc))
pub fn Connection::load_extension_file(
  self : Connection,
  file : String,
  entrypoint? : String = "",
  loc~ : SourceLoc,
) -> Connection raise SqliteError {
  let zFile = @utf8.encode(file)
  let zProc = @utf8.encode(entrypoint)
  let rescode = @native.sqlite3_load_extension(self.0, zFile, zProc)
  if rescode != SQLITE_OK {
    raise SqliteError((rescode, loc))
  }
  self
}

///|
#callsite(autofill(loc))
pub fn Connection::load_extension(
  self : Connection,
  loader : (Connection) -> Unit raise SqliteError,
  loc~ : SourceLoc,
) -> Connection raise SqliteError {
  loader(self)
  self
}

///|
#callsite(autofill(loc))
pub fn Connection::disable_load_extension(
  self : Connection,
  loc~ : SourceLoc,
) -> Unit raise SqliteError {
  let rescode = @native.sqlite3_enable_load_extension(self.0, 0)
  if rescode != SQLITE_OK {
    raise SqliteError((rescode, loc))
  }
}

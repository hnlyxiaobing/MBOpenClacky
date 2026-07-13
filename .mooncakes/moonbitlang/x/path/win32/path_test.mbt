// Copyright 2025 International Digital Economy Academy
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

///|
test "basename/dirname" {
  @debug.debug_inspect(Path::basename("a\\b"), content="b")
  @debug.debug_inspect(Path::dirname("a\\b"), content="a")
  @debug.debug_inspect(Path::basename("a\\b\\"))
  @debug.debug_inspect(Path::dirname("a\\b\\"), content="a\\b")
}

///|
test "dirname/edge cases" {
  @debug.debug_inspect(Path::dirname("\\"), content="\\")
  @debug.debug_inspect(Path::dirname("\\\\"), content="\\\\")
  @debug.debug_inspect(Path::dirname("\\\\\\"), content="\\\\\\")
  @debug.debug_inspect(Path::dirname("\\\\\\\\"), content="\\\\\\\\")
  @debug.debug_inspect(Path::dirname("a\\"), content="a")
  @debug.debug_inspect(Path::dirname("a\\\\"), content="a")
  @debug.debug_inspect(Path::dirname("a\\\\\\"), content="a")
  @debug.debug_inspect(Path::dirname("a\\\\\\\\"), content="a")
  @debug.debug_inspect(Path::dirname("\\a"), content="\\")
  @debug.debug_inspect(Path::dirname("\\\\a"), content="\\\\")
  @debug.debug_inspect(Path::dirname("\\\\\\a"), content="\\\\\\")
  @debug.debug_inspect(Path::dirname("\\\\\\\\a"), content="\\\\\\\\")
}

///|
test "extname" {
  @debug.debug_inspect(Path::extname("project\\main.mbt.md"), content=".md")
  @debug.debug_inspect(Path::extname("project\\"), content="")
}

///|
test "is_absolute" {
  // absolute path cases
  //
  // verbatim symlink 
  json_inspect(Path::is_absolute("\\\\?\\GLOBALROOT\\file"), content=true)
  // verbatim unc 
  json_inspect(
    Path::is_absolute("\\\\?\\UNC\\server\\share\\file"),
    content=true,
  )
  // verbatim volume letter
  json_inspect(Path::is_absolute("\\\\?\\C:\\file"), content=true)
  // verbatim volume guid 
  json_inspect(
    Path::is_absolute(
      "\\\\?\\Volume{12345678-1234-1234-1234-1234567890ab}\\file",
    ),
    content=true,
  )
  // device namespace
  json_inspect(Path::is_absolute("\\\\.\\COM56"), content=true)
  // unc 
  json_inspect(Path::is_absolute("\\\\server\\share\\file"), content=true)
  // volume letter root 
  json_inspect(Path::is_absolute("C:\\"), content=true)
  // relative path cases
  // 
  // volume letter relative path
  json_inspect(Path::is_absolute("C:folder\\file"), content=false)
  json_inspect(Path::is_absolute("Users\\user"), content=false)
  json_inspect(Path::is_absolute(""), content=false)
}

///|
test "join" {
  @debug.debug_inspect(Path::join("a", "\\b"), content="\\b")
  @debug.debug_inspect(Path::join("a\\", "b"), content="a\\b")
  @debug.debug_inspect(Path::join("a", "b"), content="a\\b")
}

///|
test "relative" {
  let from = "C:\\Users\\user_name"
  let to = "C:\\Users\\user_name\\proj_a"
  @debug.debug_inspect(Path::relative(base=from, to), content="proj_a")
  let from = "C:\\Users\\user_name\\proj_a"
  let to = "C:\\Users\\user_name"
  @debug.debug_inspect(Path::relative(base=from, to), content="..")
  let from = "C:\\Users\\user_name"
  let to = "C:\\Users\\user_name"
  @debug.debug_inspect(Path::relative(base=from, to), content="")
  let from = "C:\\Users\\user_name\\proj_a"
  let to = "C:\\Users\\user_name\\proj_b"
  @debug.debug_inspect(Path::relative(base=from, to), content="..\\proj_b")
}

///|
test "normalize" {
  @debug.debug_inspect(Path::normalize("a\\.\\b\\..\\c\\"), content="a\\c")
  @debug.debug_inspect(Path::normalize("\\a\\b\\..\\..\\c\\."), content="\\c")
  @debug.debug_inspect(Path::normalize("a\\b\\c\\.."), content="a\\b")
}

///|
test "resolve" {
  @debug.debug_inspect(Path::resolve("\\a\\..\\b\\c"), content="\\b\\c")
  @debug.debug_inspect(Path::resolve("\\a\\b\\c\\..\\..\\.."), content="\\")
  @debug.debug_inspect(Path::resolve("\\a\\b\\.\\c"), content="\\a\\b\\c")
  @debug.debug_inspect(Path::resolve("\\a\\b\\c\\."), content="\\a\\b\\c")
}

///|
test "basename edge cases" {
  // Empty path
  @debug.debug_inspect(Path::basename(""), content="")

  // Root paths
  @debug.debug_inspect(Path::basename("\\"), content="")
  @debug.debug_inspect(Path::basename("\\\\"), content="")
  @debug.debug_inspect(Path::basename("\\\\\\"), content="")
  @debug.debug_inspect(Path::basename("C:\\"), content="")

  // Single character paths
  @debug.debug_inspect(Path::basename("a"), content="a")
  @debug.debug_inspect(Path::basename("\\a"), content="a")
  @debug.debug_inspect(Path::basename("C:a"), content="a")
  @debug.debug_inspect(Path::basename("C:\\a"), content="a")

  // Paths with trailing backslashes
  @debug.debug_inspect(Path::basename("a\\"), content="")
  @debug.debug_inspect(Path::basename("a\\b\\"), content="")
  @debug.debug_inspect(Path::basename("C:\\a\\b\\"), content="")
  @debug.debug_inspect(Path::basename("a\\b\\\\"), content="")

  // Hidden files (starting with dot)
  @debug.debug_inspect(Path::basename("C:\\a\\.hidden"), content=".hidden")
  @debug.debug_inspect(Path::basename("C:\\.hidden"), content=".hidden")
  @debug.debug_inspect(Path::basename(".hidden"), content=".hidden")
  @debug.debug_inspect(Path::basename("C:\\a\\."), content=".")
  @debug.debug_inspect(Path::basename("C:\\a\\.."), content="..")

  // Complex paths
  @debug.debug_inspect(Path::basename(".\\a\\b"), content="b")
  @debug.debug_inspect(Path::basename("..\\a\\b"), content="b")
  @debug.debug_inspect(Path::basename("a\\..\\b"), content="b")
  @debug.debug_inspect(Path::basename("C:\\a\\..\\b"), content="b")

  // Paths with special characters and spaces
  @debug.debug_inspect(Path::basename("C:\\a\\b c"), content="b c")
  @debug.debug_inspect(Path::basename("C:\\a\\b-c"), content="b-c")
  @debug.debug_inspect(Path::basename("C:\\a\\b_c"), content="b_c")
  @debug.debug_inspect(Path::basename("C:\\a\\b.c.d"), content="b.c.d")
  @debug.debug_inspect(Path::basename("C:\\Program Files\\app"), content="app")

  // UNC paths
  @debug.debug_inspect(Path::basename("\\\\server\\share\\file"), content="file")
  @debug.debug_inspect(Path::basename("\\\\server\\share\\folder\\file"), content="file")
  @debug.debug_inspect(Path::basename("\\\\server\\share\\"), content="")

  // Verbatim paths
  @debug.debug_inspect(Path::basename("\\\\?\\C:\\temp\\file"), content="file")
  @debug.debug_inspect(Path::basename("\\\\?\\UNC\\server\\share\\file"), content="file")

  // Long paths
  @debug.debug_inspect(
    Path::basename("C:\\very\\long\\path\\with\\many\\components\\final"),
    content="final",
  )

  // Paths with multiple consecutive backslashes
  @debug.debug_inspect(Path::basename("a\\\\b"), content="b")
  @debug.debug_inspect(Path::basename("a\\\\\\b"), content="b")
  @debug.debug_inspect(Path::basename("C:\\a\\\\b\\\\c"), content="c")
}

///|
test "dirname edge cases" {
  // Empty path
  @debug.debug_inspect(Path::dirname(""), content="")

  // Root paths
  @debug.debug_inspect(Path::dirname("\\"), content="\\")
  @debug.debug_inspect(Path::dirname("\\\\"), content="\\\\")
  @debug.debug_inspect(Path::dirname("\\\\\\"), content="\\\\\\")
  @debug.debug_inspect(Path::dirname("C:\\"), content="C:\\")
  @debug.debug_inspect(Path::dirname("C:"), content="C:")

  // Single character paths
  @debug.debug_inspect(Path::dirname("a"), content="")
  @debug.debug_inspect(Path::dirname("\\a"), content="\\")
  @debug.debug_inspect(Path::dirname("C:a"), content="C:")
  @debug.debug_inspect(Path::dirname("C:\\a"), content="C:\\")

  // Paths with trailing backslashes
  @debug.debug_inspect(Path::dirname("a\\"), content="a")
  @debug.debug_inspect(Path::dirname("C:\\a\\"), content="C:\\a")
  @debug.debug_inspect(Path::dirname("a\\b\\"), content="a\\b")

  // Hidden files
  @debug.debug_inspect(Path::dirname("C:\\.hidden"), content="C:\\")
  @debug.debug_inspect(Path::dirname("C:\\a\\.hidden"), content="C:\\a")
  @debug.debug_inspect(Path::dirname(".hidden"), content="")
  @debug.debug_inspect(Path::dirname("C:\\a\\."), content="C:\\a")
  @debug.debug_inspect(Path::dirname("C:\\a\\.."), content="C:\\a")

  // Complex paths
  @debug.debug_inspect(Path::dirname(".\\a"), content=".")
  @debug.debug_inspect(Path::dirname("..\\a"), content="..")
  @debug.debug_inspect(Path::dirname("a\\..\\b"), content="a\\..")
  @debug.debug_inspect(Path::dirname("C:\\a\\..\\b"), content="C:\\a\\..")

  // UNC paths
  @debug.debug_inspect(
    Path::dirname("\\\\server\\share\\file"),
    content="\\\\server\\share\\",
  )
  @debug.debug_inspect(
    Path::dirname("\\\\server\\share\\folder\\file"),
    content="\\\\server\\share\\folder",
  )
  @debug.debug_inspect(Path::dirname("\\\\server\\share"), content="\\\\server\\share")

  // Verbatim paths
  @debug.debug_inspect(Path::dirname("\\\\?\\C:\\temp\\file"), content="\\\\?\\C:\\temp")
  @debug.debug_inspect(
    Path::dirname("\\\\?\\UNC\\server\\share\\file"),
    content="\\\\?\\UNC\\server\\share",
  )

  // Paths with multiple consecutive backslashes
  @debug.debug_inspect(Path::dirname("a\\\\b"), content="a")
  @debug.debug_inspect(Path::dirname("a\\\\\\b"), content="a")
  @debug.debug_inspect(Path::dirname("C:\\a\\\\b\\\\c"), content="C:\\a\\\\b")

  // Long paths
  @debug.debug_inspect(
    Path::dirname("C:\\very\\long\\path\\with\\many\\components"),
    content="C:\\very\\long\\path\\with\\many",
  )
}

///|
test "extname edge cases" {
  // Empty path and no extension
  @debug.debug_inspect(Path::extname(""), content="")
  @debug.debug_inspect(Path::extname("file"), content="")
  @debug.debug_inspect(Path::extname("C:\\path\\file"), content="")

  // Hidden files
  @debug.debug_inspect(Path::extname(".hidden"), content=".hidden")
  @debug.debug_inspect(Path::extname(".hidden.txt"), content=".txt")
  @debug.debug_inspect(Path::extname("C:\\path\\.hidden"), content=".hidden")
  @debug.debug_inspect(Path::extname("C:\\path\\.hidden.txt"), content=".txt")

  // Dot files and directories
  @debug.debug_inspect(Path::extname("."), content=".")
  @debug.debug_inspect(Path::extname(".."), content=".")
  @debug.debug_inspect(Path::extname(".\\file"), content="")
  @debug.debug_inspect(Path::extname("..\\file"), content="")
  @debug.debug_inspect(Path::extname("C:\\a\\."), content=".")
  @debug.debug_inspect(Path::extname("C:\\a\\.."), content=".")

  // Multiple extensions
  @debug.debug_inspect(Path::extname("file.tar.gz"), content=".gz")
  @debug.debug_inspect(Path::extname("archive.tar.bz2"), content=".bz2")
  @debug.debug_inspect(Path::extname("config.json.bak"), content=".bak")

  // Extensions with special characters
  @debug.debug_inspect(Path::extname("file.c++"), content=".c++")
  @debug.debug_inspect(Path::extname("file.123"), content=".123")
  @debug.debug_inspect(Path::extname("file.-"), content=".-")

  // Paths with trailing backslashes
  @debug.debug_inspect(Path::extname("file.txt\\"), content="")
  @debug.debug_inspect(Path::extname("C:\\path\\file.txt\\"), content="")

  // Extensions at different positions
  @debug.debug_inspect(Path::extname(".txt"), content=".txt")
  @debug.debug_inspect(Path::extname("a.b.c"), content=".c")
  @debug.debug_inspect(Path::extname("a."), content=".")
  @debug.debug_inspect(Path::extname("C:\\path\\a."), content=".")

  // Windows specific extensions
  @debug.debug_inspect(Path::extname("program.exe"), content=".exe")
  @debug.debug_inspect(Path::extname("library.dll"), content=".dll")
  @debug.debug_inspect(Path::extname("config.ini"), content=".ini")
  @debug.debug_inspect(Path::extname("batch.bat"), content=".bat")
  @debug.debug_inspect(Path::extname("command.cmd"), content=".cmd")

  // UNC paths with extensions
  @debug.debug_inspect(Path::extname("\\\\server\\share\\file.txt"), content=".txt")
  @debug.debug_inspect(Path::extname("\\\\?\\C:\\temp\\file.log"), content=".log")

  // Very long extensions
  @debug.debug_inspect(Path::extname("file.verylongextension"), content=".verylongextension")
}

///|
test "is_absolute advanced edge cases" {
  // Empty and whitespace
  json_inspect(Path::is_absolute(""), content=false)
  json_inspect(Path::is_absolute(" "), content=false)
  json_inspect(Path::is_absolute("  \\"), content=false)

  // Basic absolute paths
  json_inspect(Path::is_absolute("\\"), content=true)
  json_inspect(Path::is_absolute("\\\\"), content=true) // This might be interpreted as start of UNC
  json_inspect(Path::is_absolute("\\\\\\"), content=true)
  json_inspect(Path::is_absolute("C:\\"), content=true)
  json_inspect(Path::is_absolute("D:\\temp"), content=true)

  // Relative paths with drive letters
  json_inspect(Path::is_absolute("C:"), content=false)
  json_inspect(Path::is_absolute("C:temp"), content=false)
  json_inspect(Path::is_absolute("C:temp\\file"), content=false)
  json_inspect(Path::is_absolute("Z:relative"), content=false)

  // Various UNC path formats
  json_inspect(Path::is_absolute("\\\\server\\share"), content=true)
  json_inspect(Path::is_absolute("\\\\server\\share\\"), content=true)
  json_inspect(Path::is_absolute("\\\\server\\share\\file"), content=true)
  json_inspect(Path::is_absolute("\\\\localhost\\c$\\temp"), content=true)
  json_inspect(Path::is_absolute("\\\\127.0.0.1\\share\\file"), content=true)

  // Verbatim path formats
  json_inspect(Path::is_absolute("\\\\?\\C:\\"), content=true)
  json_inspect(Path::is_absolute("\\\\?\\C:\\temp"), content=true)
  json_inspect(Path::is_absolute("\\\\?\\D:\\very\\long\\path"), content=true)

  // Verbatim UNC paths
  json_inspect(Path::is_absolute("\\\\?\\UNC\\server\\share"), content=true)
  json_inspect(
    Path::is_absolute("\\\\?\\UNC\\server\\share\\file"),
    content=true,
  )

  // Device namespace paths
  json_inspect(Path::is_absolute("\\\\.\\COM1"), content=true)
  json_inspect(Path::is_absolute("\\\\.\\LPT1"), content=true)
  json_inspect(Path::is_absolute("\\\\.\\PRN"), content=true)
  json_inspect(Path::is_absolute("\\\\.\\AUX"), content=true)
  json_inspect(Path::is_absolute("\\\\.\\NUL"), content=true)
  json_inspect(Path::is_absolute("\\\\.\\CON"), content=true)
  json_inspect(Path::is_absolute("\\\\.\\PhysicalDrive0"), content=true)

  // Volume GUID paths
  json_inspect(
    Path::is_absolute("\\\\?\\Volume{12345678-1234-1234-1234-1234567890ab}\\"),
    content=true,
  )
  json_inspect(
    Path::is_absolute(
      "\\\\?\\Volume{12345678-1234-1234-1234-1234567890ab}\\temp",
    ),
    content=true,
  )

  // Global root paths
  json_inspect(
    Path::is_absolute("\\\\?\\GLOBALROOT\\Device\\HarddiskVolume1\\"),
    content=true,
  )
  json_inspect(
    Path::is_absolute("\\\\?\\GLOBALROOT\\Device\\HarddiskVolume1\\temp"),
    content=true,
  )

  // Relative paths
  json_inspect(Path::is_absolute("temp"), content=false)
  json_inspect(Path::is_absolute("temp\\file"), content=false)
  json_inspect(Path::is_absolute(".\\temp"), content=false)
  json_inspect(Path::is_absolute("..\\temp"), content=false)
  json_inspect(Path::is_absolute("folder\\subfolder"), content=false)

  // Edge cases with dots
  json_inspect(Path::is_absolute("."), content=false)
  json_inspect(Path::is_absolute(".."), content=false)
  json_inspect(Path::is_absolute(".\\"), content=false)
  json_inspect(Path::is_absolute("..\\"), content=false)
  json_inspect(Path::is_absolute("\\."), content=true)
  json_inspect(Path::is_absolute("\\.."), content=true)

  // Case sensitivity tests (Windows is case-insensitive)
  json_inspect(Path::is_absolute("c:\\"), content=true)
  json_inspect(Path::is_absolute("C:\\"), content=true)
  json_inspect(Path::is_absolute("z:\\temp"), content=true)
  json_inspect(Path::is_absolute("Z:\\temp"), content=true)
}

///|
test "join edge cases" {
  // Empty strings
  @debug.debug_inspect(Path::join("", ""), content="")
  @debug.debug_inspect(
    Path::join("a", ""),
    content=(
      #|a
    ),
  )
  @debug.debug_inspect(Path::join("", "b"), content="b")

  // Both paths are absolute - second wins
  @debug.debug_inspect(Path::join("C:\\a", "D:\\b"), content="D:\\b")
  @debug.debug_inspect(Path::join("C:\\a\\c", "\\b"), content="\\b")
  @debug.debug_inspect(
    Path::join("\\\\server1\\share1", "\\\\server2\\share2"),
    content="\\\\server2\\share2",
  )

  // Drive letter combinations
  @debug.debug_inspect(Path::join("C:", "temp"), content="C:\\temp")
  @debug.debug_inspect(Path::join("C:\\", "temp"), content="C:\\temp")
  @debug.debug_inspect(Path::join("C:\\folder", "temp"), content="C:\\folder\\temp")
  @debug.debug_inspect(Path::join("C:folder", "temp"), content="C:folder\\temp")

  // Various separator combinations
  @debug.debug_inspect(Path::join("a", "b\\c"), content="a\\b\\c")
  @debug.debug_inspect(Path::join("a\\", "b\\c"), content="a\\b\\c")
  @debug.debug_inspect(Path::join("a\\\\", "b"), content="a\\\\b")
  @debug.debug_inspect(Path::join("a\\\\\\", "b"), content="a\\\\\\b")

  // Relative path components
  @debug.debug_inspect(Path::join("a", ".\\b"), content="a\\.\\b")
  @debug.debug_inspect(Path::join("a", "..\\b"), content="a\\..\\b")
  @debug.debug_inspect(Path::join(".\\a", "b"), content=".\\a\\b")
  @debug.debug_inspect(Path::join("..\\a", "b"), content="..\\a\\b")

  // UNC paths
  @debug.debug_inspect(
    Path::join("\\\\server\\share", "folder"),
    content="\\\\server\\share\\folder",
  )
  @debug.debug_inspect(
    Path::join("\\\\server\\share\\", "folder"),
    content="\\\\server\\share\\folder",
  )

  // Verbatim paths
  @debug.debug_inspect(
    Path::join("\\\\?\\C:\\temp", "file"),
    content="\\\\?\\C:\\temp\\file",
  )
  @debug.debug_inspect(
    Path::join("\\\\?\\C:\\temp\\", "file"),
    content="\\\\?\\C:\\temp\\file",
  )

  // Root paths
  @debug.debug_inspect(Path::join("\\", "a"), content="\\a")
  @debug.debug_inspect(Path::join("\\", "\\a"), content="\\a")
  @debug.debug_inspect(Path::join("\\\\", "a"), content="\\\\a")

  // Hidden files
  @debug.debug_inspect(Path::join("a", ".hidden"), content="a\\.hidden")
  @debug.debug_inspect(Path::join("C:\\a", ".hidden"), content="C:\\a\\.hidden")

  // Complex combinations
  @debug.debug_inspect(Path::join("a\\b", "..\\c"), content="a\\b\\..\\c")
  @debug.debug_inspect(Path::join("C:\\a\\b", "..\\c"), content="C:\\a\\b\\..\\c")
  @debug.debug_inspect(Path::join("", "C:\\abs"), content="C:\\abs")

  // Multiple consecutive separators
  @debug.debug_inspect(Path::join("a\\\\b", "c"), content="a\\\\b\\c")
  @debug.debug_inspect(Path::join("a", "b\\\\c"), content="a\\b\\\\c")

  // Special Windows device names
  @debug.debug_inspect(Path::join("C:\\temp", "CON"), content="C:\\temp\\CON")
  @debug.debug_inspect(Path::join("C:\\temp", "PRN.txt"), content="C:\\temp\\PRN.txt")
}

///|
test "normalize edge cases" {
  // Empty path
  @debug.debug_inspect(Path::normalize(""), content="")

  // Simple dot resolution
  @debug.debug_inspect(Path::normalize("."), content="")
  @debug.debug_inspect(Path::normalize(".\\"), content="")
  @debug.debug_inspect(Path::normalize("a\\."), content="a")
  @debug.debug_inspect(Path::normalize(".\\a"), content="a")
  @debug.debug_inspect(Path::normalize(".\\a\\"), content="a")
  @debug.debug_inspect(Path::normalize("a\\.\\b"), content="a\\b")

  // Double dot resolution
  @debug.debug_inspect(Path::normalize(".."), content="..")
  @debug.debug_inspect(Path::normalize("..\\"), content="..")
  @debug.debug_inspect(Path::normalize("a\\.."), content="")
  @debug.debug_inspect(Path::normalize("a\\..\\"), content="")
  @debug.debug_inspect(Path::normalize("..\\a"), content="..\\a")
  @debug.debug_inspect(Path::normalize("a\\..\\b"), content="b")
  @debug.debug_inspect(Path::normalize("a\\b\\.."), content="a")
  @debug.debug_inspect(Path::normalize("a\\b\\..\\"), content="a")
  @debug.debug_inspect(Path::normalize("a\\b\\..\\c"), content="a\\c")

  // Multiple consecutive separators
  @debug.debug_inspect(Path::normalize("a\\\\b"), content="a\\b")
  @debug.debug_inspect(Path::normalize("a\\\\\\b"), content="a\\b")
  @debug.debug_inspect(Path::normalize("\\\\a\\\\b"), content="\\\\a\\\\b")
  @debug.debug_inspect(Path::normalize("\\\\\\a\\\\\\b"), content="\\\\\\a\\\\\\b")

  // Drive letter paths
  @debug.debug_inspect(Path::normalize("C:\\.\\temp"), content="C:\\temp")
  @debug.debug_inspect(Path::normalize("C:\\..\\temp"), content="C:\\temp")
  @debug.debug_inspect(Path::normalize("C:\\folder\\..\\temp"), content="C:\\temp")
  @debug.debug_inspect(Path::normalize("C:temp\\.\\file"), content="C:temp\\file")

  // UNC path normalization
  @debug.debug_inspect(
    Path::normalize("\\\\server\\share\\.\\folder"),
    content="\\\\server\\share\\folder",
  )
  @debug.debug_inspect(
    Path::normalize("\\\\server\\share\\folder\\..\\file"),
    content="\\\\server\\share\\file",
  )

  // Complex combinations
  @debug.debug_inspect(Path::normalize("a\\.\\b\\..\\c"), content="a\\c")
  @debug.debug_inspect(Path::normalize(".\\a\\..\\b\\.\\c"), content="b\\c")
  @debug.debug_inspect(Path::normalize("a\\b\\..\\..\\c"), content="c")
  @debug.debug_inspect(Path::normalize("a\\b\\..\\..\\..\\c"), content="..\\c")

  // Root paths with dots
  @debug.debug_inspect(Path::normalize("\\."), content="\\")
  @debug.debug_inspect(Path::normalize("\\./"), content="\\./")
  @debug.debug_inspect(Path::normalize("\\.."), content="\\")
  @debug.debug_inspect(Path::normalize("\\..\\"), content="\\")
  @debug.debug_inspect(Path::normalize("\\a\\.."), content="\\")
  @debug.debug_inspect(Path::normalize("\\a\\..\\"), content="\\")
  @debug.debug_inspect(Path::normalize("\\a\\..\\b"), content="\\b")

  // Preserve trailing backslashes where appropriate
  @debug.debug_inspect(Path::normalize("a\\b\\c\\"), content="a\\b\\c")
  @debug.debug_inspect(Path::normalize("a\\.\\b\\..\\c\\"), content="a\\c")

  // Hidden files
  @debug.debug_inspect(Path::normalize(".\\.hidden"), content=".hidden")
  @debug.debug_inspect(Path::normalize("a\\.\\.hidden"), content="a\\.hidden")
  @debug.debug_inspect(Path::normalize("a\\..\\..hidden"), content="..hidden")

  // Verbatim paths (should preserve structure)
  @debug.debug_inspect(
    Path::normalize("\\\\?\\C:\\temp\\.\\file"),
    content="\\\\?\\C:\\temp\\file",
  )
  @debug.debug_inspect(
    Path::normalize("\\\\?\\UNC\\server\\share\\folder\\..\\file"),
    content="\\\\?\\UNC\\server\\share\\file",
  )
}

///|
test "relative edge cases" {
  // Same paths
  let same1 = "C:\\Users\\user"
  let same2 = "C:\\Users\\user"
  @debug.debug_inspect(Path::relative(base=same1, same2), content="")

  // Same paths with different normalization
  @debug.debug_inspect(Path::relative(base="C:\\a\\b", "C:\\a\\.\\b"), content="")
  @debug.debug_inspect(Path::relative(base="C:\\a\\b", "C:\\a\\c\\..\\b"), content="")

  // Different drives should return empty (different prefixes)
  @debug.debug_inspect(Path::relative(base="C:\\temp", "D:\\temp"), content="")
  @debug.debug_inspect(Path::relative(base="C:\\Users", "D:\\Files"), content="")

  // Root to various paths
  @debug.debug_inspect(Path::relative(base="C:\\", "C:\\Users"), content="Users")
  @debug.debug_inspect(Path::relative(base="C:\\Users", "C:\\"), content="..")

  // Deep nesting
  @debug.debug_inspect(
    Path::relative(base="C:\\a\\b\\c\\d", "C:\\a\\b\\e\\f"),
    content="..\\..\\e\\f",
  )
  @debug.debug_inspect(
    Path::relative(base="C:\\a\\b\\c\\d\\e", "C:\\a\\f"),
    content="..\\..\\..\\..\\f",
  )

  // Hidden files and directories
  @debug.debug_inspect(
    Path::relative(base="C:\\Users\\.config", "C:\\Users\\.local"),
    content="..\\.local",
  )
  @debug.debug_inspect(
    Path::relative(base="C:\\Users", "C:\\Users\\.hidden"),
    content=".hidden",
  )

  // Paths with dots
  @debug.debug_inspect(
    Path::relative(base="C:\\Users\\user", "C:\\Users\\user\\."),
    content="",
  )
  @debug.debug_inspect(
    Path::relative(base="C:\\Users\\user\\.", "C:\\Users\\user"),
    content="",
  )
  @debug.debug_inspect(
    Path::relative(base="C:\\Users\\user", "C:\\Users\\user\\.."),
    content="..",
  )

  // UNC paths
  @debug.debug_inspect(
    Path::relative(
      base="\\\\server\\share\\folder1",
      "\\\\server\\share\\folder2",
    ),
    content="..\\folder2",
  )
  @debug.debug_inspect(
    Path::relative(base="\\\\server1\\share", "\\\\server2\\share"),
    content="",
  ) // Different prefixes

  // Complex relative navigation
  @debug.debug_inspect(
    Path::relative(base="C:\\a\\b\\c", "C:\\a\\b\\c\\..\\d"),
    content="..\\d",
  )
  @debug.debug_inspect(
    Path::relative(base="C:\\a\\b\\c\\..\\d", "C:\\a\\b\\c"),
    content="..\\c",
  )

  // Mixed case drives (Windows is case-insensitive, but let's test)
  @debug.debug_inspect(Path::relative(base="c:\\temp", "C:\\temp\\file"), content="")
  @debug.debug_inspect(Path::relative(base="C:\\TEMP", "c:\\temp\\FILE"), content="")
}

///|
test "resolve edge cases" {
  // Already absolute paths should be normalized
  @debug.debug_inspect(Path::resolve("C:\\a\\.\\b"), content="C:\\a\\b")
  @debug.debug_inspect(Path::resolve("C:\\a\\..\\b"), content="C:\\b")
  @debug.debug_inspect(Path::resolve("C:\\a\\b\\..\\..\\c"), content="C:\\c")

  // UNC paths
  @debug.debug_inspect(
    Path::resolve("\\\\server\\share\\.\\file"),
    content="\\\\server\\share\\file",
  )
  @debug.debug_inspect(
    Path::resolve("\\\\server\\share\\folder\\..\\file"),
    content="\\\\server\\share\\file",
  )

  // Relative paths with current drive
  // Note: These tests assume we're running on Windows with a current drive
  // In cross-platform testing, these might need to be conditional

  // Verbatim paths
  @debug.debug_inspect(
    Path::resolve("\\\\?\\C:\\temp\\.\\file"),
    content="\\\\?\\C:\\temp\\file",
  )
}

///|
test "constants and separators" {
  // Test delimiter constant (semicolon on Windows)
  @debug.debug_inspect(delimiter, content=";")

  // Test separator constant (backslash on Windows)
  @debug.debug_inspect(sep, content="\\")
}

///|
test "Windows-specific path behaviors" {
  // Test case insensitivity awareness (functions should handle but preserve case)
  @debug.debug_inspect(Path::basename("C:\\Temp\\File.TXT"), content="File.TXT")
  @debug.debug_inspect(Path::dirname("C:\\TEMP\\file.txt"), content="C:\\TEMP")
  @debug.debug_inspect(Path::extname("FILE.EXE"), content=".EXE")

  // Test drive letter edge cases
  json_inspect(Path::is_absolute("A:"), content=false) // Relative to current dir on drive A
  json_inspect(Path::is_absolute("Z:\\"), content=true) // Root of drive Z
  @debug.debug_inspect(Path::join("C:", "temp"), content="C:\\temp") // Relative path on drive C
  @debug.debug_inspect(Path::join("C:\\", "temp"), content="C:\\temp") // Absolute path on drive C

  // Test UNC path components
  @debug.debug_inspect(Path::basename("\\\\server\\share"), content="")
  @debug.debug_inspect(Path::dirname("\\\\server\\share"), content="\\\\server\\share")
  @debug.debug_inspect(Path::dirname("\\\\server"), content="\\\\")

  // Test verbatim path handling
  @debug.debug_inspect(Path::basename("\\\\?\\C:\\very\\long\\path\\file"), content="file")
  @debug.debug_inspect(
    Path::dirname("\\\\?\\C:\\very\\long\\path\\file"),
    content="\\\\?\\C:\\very\\long\\path",
  )

  // Test device namespace paths
  @debug.debug_inspect(Path::basename("\\\\.\\COM1"), content="")
  @debug.debug_inspect(Path::dirname("\\\\.\\COM1"), content="\\\\.\\COM1")
}

///|
test "join/windows relative path but specifies drive letter" {
  @debug.debug_inspect(Path::join("lhs", "C:rhs"), content="C:rhs")
  @debug.debug_inspect(Path::join("C:lhs", "C:rhs"), content="C:lhs\\rhs")
  @debug.debug_inspect(Path::join("C:lhs", "D:rhs"), content="D:rhs")
}

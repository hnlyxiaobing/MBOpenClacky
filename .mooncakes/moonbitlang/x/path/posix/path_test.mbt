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
  @debug.debug_inspect(Path::basename("a/b"), content="b")
  @debug.debug_inspect(Path::dirname("a/b"), content="a")
  @debug.debug_inspect(Path::basename("a/b/"))
  @debug.debug_inspect(Path::dirname("a/b/"), content="a/b")
}

///|
test "dirname/edge cases" {
  // Root paths
  @debug.debug_inspect(Path::dirname("/"), content="/")
  @debug.debug_inspect(Path::dirname("///"), content="///")
  @debug.debug_inspect(Path::dirname("////"), content="////")
  // POSIX platform specific cases
  @debug.debug_inspect(Path::dirname("//"), content="//")
  // relative paths
  @debug.debug_inspect(Path::dirname("a"), content="")
  // relative paths with trailing slashes
  @debug.debug_inspect(Path::dirname("a/"), content="a")
  @debug.debug_inspect(Path::dirname("a//"), content="a")
  @debug.debug_inspect(Path::dirname("a///"), content="a")
  @debug.debug_inspect(Path::dirname("a////"), content="a")

  // Root path with single directory
  @debug.debug_inspect(Path::dirname("/a"), content="/")
  @debug.debug_inspect(Path::dirname("///a"), content="///")
  // POSIX platform specific cases with single directory
  @debug.debug_inspect(Path::dirname("//a"), content="//")
  // Empty path 
  @debug.debug_inspect(Path::dirname(""), content="")
  // path with `.` and `..`, Path::dirname doesn't resolve them.
  @debug.debug_inspect(Path::dirname("./a"), content=".")
  @debug.debug_inspect(Path::dirname("../a"), content="..")
  @debug.debug_inspect(Path::dirname("a/."), content="a")
  @debug.debug_inspect(Path::dirname("a/.."), content="a")

  // Paths with multiple consecutive slashes
  @debug.debug_inspect(Path::dirname("a//b"), content="a")
  @debug.debug_inspect(Path::dirname("a///b"), content="a")
  @debug.debug_inspect(Path::dirname("/a//b//c"), content="/a//b")
}

///|
test "basename/edge cases" {
  // Root paths
  @debug.debug_inspect(Path::basename("/"), content="")
  @debug.debug_inspect(Path::basename("///"), content="")
  @debug.debug_inspect(Path::basename("////"), content="")
  // POSIX platform specific cases
  @debug.debug_inspect(Path::basename("//"), content="")
  // relative paths
  @debug.debug_inspect(Path::basename("a"), content="a")
  // relative paths with trailing slashes
  @debug.debug_inspect(Path::basename("a/"), content="")
  @debug.debug_inspect(Path::basename("a//"), content="")
  @debug.debug_inspect(Path::basename("a///"), content="")
  @debug.debug_inspect(Path::basename("a////"), content="")

  // Root path with single directory
  @debug.debug_inspect(Path::basename("/a"), content="a")
  @debug.debug_inspect(Path::basename("///a"), content="a")
  // POSIX platform specific cases with single directory
  @debug.debug_inspect(Path::basename("//a"), content="a")
  // Empty path 
  @debug.debug_inspect(Path::basename(""), content="")
  // path with `.` and `..`, Path::basename doesn't resolve them.
  @debug.debug_inspect(Path::basename("./a"), content="a")
  @debug.debug_inspect(Path::basename("../a"), content="a")
  @debug.debug_inspect(Path::basename("a/."), content=".")
  @debug.debug_inspect(Path::basename("a/.."), content="..")

  // Paths with multiple consecutive slashes
  @debug.debug_inspect(Path::basename("a//b"), content="b")
  @debug.debug_inspect(Path::basename("a///b"), content="b")
  @debug.debug_inspect(Path::basename("/a//b//c"), content="c")
}

///|
test "extname" {
  @debug.debug_inspect(Path::extname("project/main.mbt.md"), content=".md")
  @debug.debug_inspect(Path::extname("project/"), content="")
}

///|
test "is_absolute" {
  json_inspect(Path::is_absolute("/home/user"), content=true)
  json_inspect(Path::is_absolute("home/user"), content=false)
  json_inspect(Path::is_absolute(""), content=false)
}

///|
test "join" {
  @debug.debug_inspect(Path::join("a", "/b"), content="/b")
  @debug.debug_inspect(Path::join("a/", "b"), content="a/b")
  @debug.debug_inspect(Path::join("a", "b"), content="a/b")
  @debug.debug_inspect(Path::join("", ""))
}

///|
test "relative" {
  let from = "/home/user_name"
  let to = "/home/user_name/proj_a"
  @debug.debug_inspect(Path::relative(base=from, to), content="proj_a")
  let from = "/home/user_name/proj_a"
  let to = "/home/user_name"
  @debug.debug_inspect(Path::relative(base=from, to), content="..")
  let from = "/home/user_name"
  let to = "/home/user_name"
  @debug.debug_inspect(Path::relative(base=from, to), content="")
  let from = "/home/user_name/proj_a"
  let to = "/home/user_name/proj_b"
  @debug.debug_inspect(Path::relative(base=from, to), content="../proj_b")
}

///|
test "normalize" {
  @debug.debug_inspect(Path::normalize("a/./b/../c/"), content="a/c")
  @debug.debug_inspect(Path::normalize("/a/b/../../c/."), content="/c")
  @debug.debug_inspect(Path::normalize("a/b/c/.."), content="a/b")
  @debug.debug_inspect(Path::normalize(""))
}

///|
test "resolve" {
  @debug.debug_inspect(Path::resolve("/a/../b/c"), content="/b/c")
  @debug.debug_inspect(Path::resolve("/a/b/c/../../.."), content="/")
  @debug.debug_inspect(Path::resolve("/a/./b/c"), content="/a/b/c")
}

///|
test "extname edge cases" {
  // Empty path and no extension
  @debug.debug_inspect(Path::extname(""), content="")
  @debug.debug_inspect(Path::extname("file"), content="")
  @debug.debug_inspect(Path::extname("/path/file"), content="")

  // Hidden files
  @debug.debug_inspect(Path::extname(".hidden"), content=".hidden")
  @debug.debug_inspect(Path::extname(".hidden.txt"), content=".txt")
  @debug.debug_inspect(Path::extname("/path/.hidden"), content=".hidden")
  @debug.debug_inspect(Path::extname("/path/.hidden.txt"), content=".txt")

  // Dot files and directories
  @debug.debug_inspect(Path::extname("."), content=".")
  @debug.debug_inspect(Path::extname(".."), content=".")
  @debug.debug_inspect(Path::extname("./file"), content="")
  @debug.debug_inspect(Path::extname("../file"), content="")
  @debug.debug_inspect(Path::extname("/a/."), content=".")
  @debug.debug_inspect(Path::extname("/a/.."), content=".")

  // Multiple extensions
  @debug.debug_inspect(Path::extname("file.tar.gz"), content=".gz")
  @debug.debug_inspect(Path::extname("archive.tar.bz2"), content=".bz2")
  @debug.debug_inspect(Path::extname("config.json.bak"), content=".bak")

  // Extensions with special characters
  @debug.debug_inspect(Path::extname("file.c++"), content=".c++")
  @debug.debug_inspect(Path::extname("file.123"), content=".123")
  @debug.debug_inspect(Path::extname("file.-"), content=".-")

  // Paths with trailing slashes
  @debug.debug_inspect(Path::extname("file.txt/"), content="")
  @debug.debug_inspect(Path::extname("/path/file.txt/"), content="")

  // Extensions at different positions
  @debug.debug_inspect(Path::extname(".txt"), content=".txt")
  @debug.debug_inspect(Path::extname("a.b.c"), content=".c")
  @debug.debug_inspect(Path::extname("a."), content=".")
  @debug.debug_inspect(Path::extname("/path/a."), content=".")

  // Very long extensions
  @debug.debug_inspect(Path::extname("file.verylongextension"), content=".verylongextension")
}

///|
test "is_absolute edge cases" {
  // Empty and whitespace
  json_inspect(Path::is_absolute(""), content=false)
  json_inspect(Path::is_absolute(" "), content=false)
  json_inspect(Path::is_absolute("  /"), content=false)

  // Various absolute path formats
  json_inspect(Path::is_absolute("/"), content=true)
  json_inspect(Path::is_absolute("//"), content=true)
  json_inspect(Path::is_absolute("///"), content=true)
  json_inspect(Path::is_absolute("/a"), content=true)
  json_inspect(Path::is_absolute("/a/b"), content=true)

  // Relative paths
  json_inspect(Path::is_absolute("a"), content=false)
  json_inspect(Path::is_absolute("./a"), content=false)
  json_inspect(Path::is_absolute("../a"), content=false)
  json_inspect(Path::is_absolute("a/b"), content=false)
  json_inspect(Path::is_absolute("a/../b"), content=false)

  // Edge cases with dots
  json_inspect(Path::is_absolute("."), content=false)
  json_inspect(Path::is_absolute(".."), content=false)
  json_inspect(Path::is_absolute("./"), content=false)
  json_inspect(Path::is_absolute("../"), content=false)
  json_inspect(Path::is_absolute("/."), content=true)
  json_inspect(Path::is_absolute("/.."), content=true)
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

  // Both paths are absolute
  @debug.debug_inspect(Path::join("/a", "/b"), content="/b")
  @debug.debug_inspect(Path::join("/a/c", "/b"), content="/b")

  // Various separator combinations
  @debug.debug_inspect(Path::join("a", "b/c"), content="a/b/c")
  @debug.debug_inspect(Path::join("a/", "b/c"), content="a/b/c")
  @debug.debug_inspect(Path::join("a//", "b"), content="a//b")
  @debug.debug_inspect(Path::join("a///", "b"), content="a///b")

  // Relative path components
  @debug.debug_inspect(Path::join("a", "./b"), content="a/./b")
  @debug.debug_inspect(Path::join("a", "../b"), content="a/../b")
  @debug.debug_inspect(Path::join("./a", "b"), content="./a/b")
  @debug.debug_inspect(Path::join("../a", "b"), content="../a/b")

  // Root paths
  @debug.debug_inspect(Path::join("/", "a"), content="/a")
  @debug.debug_inspect(Path::join("/", "/a"), content="/a")
  @debug.debug_inspect(Path::join("//", "a"), content="//a")

  // Hidden files
  @debug.debug_inspect(Path::join("a", ".hidden"), content="a/.hidden")
  @debug.debug_inspect(Path::join("/a", ".hidden"), content="/a/.hidden")

  // Complex combinations
  @debug.debug_inspect(Path::join("a/b", "../c"), content="a/b/../c")
  @debug.debug_inspect(Path::join("/a/b", "../c"), content="/a/b/../c")
  @debug.debug_inspect(Path::join("", "/abs"), content="/abs")

  // Multiple consecutive separators
  @debug.debug_inspect(Path::join("a//b", "c"), content="a//b/c")
  @debug.debug_inspect(Path::join("a", "b//c"), content="a/b//c")
}

///|
test "normalize edge cases" {
  // Empty path
  @debug.debug_inspect(Path::normalize(""), content="")

  // Simple dot resolution
  @debug.debug_inspect(Path::normalize("."), content="")
  @debug.debug_inspect(Path::normalize("./"), content="")
  @debug.debug_inspect(Path::normalize("a/."), content="a")
  @debug.debug_inspect(Path::normalize("a/./"), content="a")
  @debug.debug_inspect(Path::normalize("./a"), content="a")
  @debug.debug_inspect(Path::normalize("./a/"), content="a")
  @debug.debug_inspect(Path::normalize("a/./b"), content="a/b")

  // Double dot resolution
  @debug.debug_inspect(Path::normalize(".."), content="..")
  @debug.debug_inspect(Path::normalize("../"), content="..")
  @debug.debug_inspect(Path::normalize("a/.."), content="")
  @debug.debug_inspect(Path::normalize("a/../"), content="")
  @debug.debug_inspect(Path::normalize("../a"), content="../a")
  @debug.debug_inspect(Path::normalize("a/../b"), content="b")
  @debug.debug_inspect(Path::normalize("a/b/.."), content="a")
  @debug.debug_inspect(Path::normalize("a/b/../"), content="a")
  @debug.debug_inspect(Path::normalize("a/b/../c"), content="a/c")

  // Multiple consecutive separators
  @debug.debug_inspect(Path::normalize("a//b"), content="a/b")
  @debug.debug_inspect(Path::normalize("a///b"), content="a/b")
  @debug.debug_inspect(Path::normalize("//a//b"), content="//a/b")
  @debug.debug_inspect(Path::normalize("///a///b"), content="/a/b")

  // Complex combinations
  @debug.debug_inspect(Path::normalize("a/./b/../c"), content="a/c")
  @debug.debug_inspect(Path::normalize("./a/../b/./c"), content="b/c")
  @debug.debug_inspect(Path::normalize("a/b/../../c"), content="c")
  @debug.debug_inspect(Path::normalize("a/b/../../../c"), content="../c")

  // Root paths with dots
  @debug.debug_inspect(Path::normalize("/."), content="/")
  @debug.debug_inspect(Path::normalize("/./"), content="/")
  @debug.debug_inspect(Path::normalize("/.."), content="/")
  @debug.debug_inspect(Path::normalize("/../"), content="/")
  @debug.debug_inspect(Path::normalize("/a/.."), content="/")
  @debug.debug_inspect(Path::normalize("/a/../"), content="/")
  @debug.debug_inspect(Path::normalize("/a/../b"), content="/b")

  // Preserve trailing slashes where appropriate
  @debug.debug_inspect(Path::normalize("a/b/c/"), content="a/b/c")
  @debug.debug_inspect(Path::normalize("a/./b/../c/"), content="a/c")

  // Hidden files
  @debug.debug_inspect(Path::normalize("./.hidden"), content=".hidden")
  @debug.debug_inspect(Path::normalize("a/./.hidden"), content="a/.hidden")
  @debug.debug_inspect(Path::normalize("a/../.hidden"), content=".hidden")
}

///|
test "relative edge cases" {
  // Same paths
  let same1 = "/home/user"
  let same2 = "/home/user"
  @debug.debug_inspect(Path::relative(base=same1, same2), content="")

  // Same paths with different normalization
  @debug.debug_inspect(Path::relative(base="/a/b", "/a/./b"), content="")
  @debug.debug_inspect(Path::relative(base="/a/b", "/a/c/../b"), content="")

  // Root to various paths
  @debug.debug_inspect(Path::relative(base="/", "/home"), content="home")
  @debug.debug_inspect(Path::relative(base="/home", "/"), content="..")

  // Deep nesting
  @debug.debug_inspect(Path::relative(base="/a/b/c/d", "/a/b/e/f"), content="../../e/f")
  @debug.debug_inspect(Path::relative(base="/a/b/c/d/e", "/a/f"), content="../../../../f")

  // Hidden files and directories
  @debug.debug_inspect(
    Path::relative(base="/home/.config", "/home/.local"),
    content="../.local",
  )
  @debug.debug_inspect(Path::relative(base="/home", "/home/.hidden"), content=".hidden")

  // Paths with dots
  @debug.debug_inspect(Path::relative(base="/home/user", "/home/user/."), content="")
  @debug.debug_inspect(Path::relative(base="/home/user/.", "/home/user"), content="")
  @debug.debug_inspect(Path::relative(base="/home/user", "/home/user/.."), content="..")

  // Complex relative navigation
  @debug.debug_inspect(Path::relative(base="/a/b/c", "/a/b/c/../d"), content="../d")
  @debug.debug_inspect(Path::relative(base="/a/b/c/../d", "/a/b/c"), content="../c")
}

///|
test "resolve edge cases" {
  // Already absolute paths should be normalized
  @debug.debug_inspect(Path::resolve("/a/./b"), content="/a/b")
  @debug.debug_inspect(Path::resolve("/a/../b"), content="/b")
  @debug.debug_inspect(Path::resolve("/a/b/../../c"), content="/c")
}

///|
test "constants and separators" {
  // Test delimiter constant
  @debug.debug_inspect(delimiter, content=":")

  // Test separator constant
  @debug.debug_inspect(sep, content="/")
}

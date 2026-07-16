///|
/// File browser panel for TUI-05 Agent Shell.
///
/// Provides a navigable file tree view of the working directory,
/// with directory entry/exit and file preview capabilities.

///|
/// Maximum number of entries to display at once.
let fb_max_visible : Int = 20

///|
/// Maximum preview content length (characters).
let fb_max_preview_chars : Int = 2000

///|
/// A single directory entry.
pub(all) struct DirEntry {
  name : String
  is_dir : Bool
  size : Int
} derive(Debug)

///|
/// File browser state.
pub(all) struct FileBrowser {
  /// Current directory path being browsed.
  mut current_path : String
  /// Sorted directory entries (directories first, then alphabetical).
  mut entries : Array[DirEntry]
  /// Index of the currently selected entry.
  mut selected_idx : Int
  /// Scroll offset for the visible window.
  mut scroll_offset : Int
  /// Preview content for the selected file (if any).
  mut preview_content : String
  /// Whether preview is currently shown.
  mut show_preview : Bool
  /// Error message if directory load failed.
  mut error_msg : String
} derive(Debug)

///|
/// Create a new FileBrowser rooted at the given path.
pub fn FileBrowser::new(path : String) -> FileBrowser {
  {
    current_path: path,
    entries: [],
    selected_idx: 0,
    scroll_offset: 0,
    preview_content: "",
    show_preview: false,
    error_msg: "",
  }
}

///|
/// Load directory entries from the filesystem.
pub fn FileBrowser::load_dir(self : FileBrowser) -> Unit {
  let path = self.current_path
  let names = @fs.read_dir(path) catch {
    IOError(msg) => {
      self.entries = []
      self.error_msg = msg
      return
    }
  }
  self.error_msg = ""
  let entries : Array[DirEntry] = []
  for name in names {
    if name == "." || name == ".." {
      continue
    }
    let full_path = join_path(path, name)
    let is_dir = @fs.is_dir(full_path) catch { _ => false }
    let size = if is_dir {
      0
    } else {
      @fs.read_file_to_bytes(full_path).length() catch {
        _ => 0
      }
    }
    entries.push({ name, is_dir, size })
  }
  sort_entries(entries)
  self.entries = entries
  self.selected_idx = 0
  self.scroll_offset = 0
}

///|
/// Navigate into the selected directory or preview a file.
pub fn FileBrowser::enter_selected(self : FileBrowser) -> Unit {
  if self.selected_idx < 0 || self.selected_idx >= self.entries.length() {
    return
  }
  let entry = self.entries[self.selected_idx]
  if entry.is_dir {
    self.current_path = join_path(self.current_path, entry.name)
    self.load_dir()
    self.show_preview = false
  } else {
    self.preview_selected()
  }
}

///|
/// Navigate to the parent directory.
pub fn FileBrowser::go_parent(self : FileBrowser) -> Unit {
  let parent = parent_path(self.current_path)
  if parent != self.current_path {
    self.current_path = parent
    self.load_dir()
    self.show_preview = false
  }
}

///|
/// Move selection up by one.
pub fn FileBrowser::move_up(self : FileBrowser) -> Unit {
  if self.selected_idx > 0 {
    self.selected_idx = self.selected_idx - 1
    if self.selected_idx < self.scroll_offset {
      self.scroll_offset = self.selected_idx
    }
    self.show_preview = false
  }
}

///|
/// Move selection down by one.
pub fn FileBrowser::move_down(self : FileBrowser) -> Unit {
  if self.selected_idx < self.entries.length() - 1 {
    self.selected_idx = self.selected_idx + 1
    if self.selected_idx >= self.scroll_offset + fb_max_visible {
      self.scroll_offset = self.selected_idx - fb_max_visible + 1
    }
    self.show_preview = false
  }
}

///|
/// Toggle preview for the currently selected file.
pub fn FileBrowser::toggle_preview(self : FileBrowser) -> Unit {
  if self.show_preview {
    self.show_preview = false
  } else {
    self.preview_selected()
  }
}

///|
/// Load preview content for the selected file entry.
fn FileBrowser::preview_selected(self : FileBrowser) -> Unit {
  if self.selected_idx < 0 || self.selected_idx >= self.entries.length() {
    return
  }
  let entry = self.entries[self.selected_idx]
  if entry.is_dir {
    self.show_preview = false
    return
  }
  let full_path = join_path(self.current_path, entry.name)
  let content = @fs.read_file_to_string(full_path) catch {
    IOError(msg) => {
      self.preview_content = "[error] \{msg}"
      self.show_preview = true
      return
    }
  }
  if content.length() > fb_max_preview_chars {
    self.preview_content = content.substring(start=0, end=fb_max_preview_chars) +
      "\n... (truncated)"
  } else {
    self.preview_content = content
  }
  self.show_preview = true
}

///|
/// Render the file browser as a Node tree.
pub fn render_file_browser(browser : FileBrowser) -> Node {
  let title = "Files: \{browser.current_path}"
  let children : Array[Node] = []
  if browser.error_msg.length() > 0 {
    children.push(
      Node::Text(
        "⚠ Error: \{browser.error_msg}",
        Style::new(fg=@color.Color::Basic(@color.BasicColor::Red)),
      ),
    )
  }
  if browser.entries.length() == 0 && browser.error_msg.length() == 0 {
    children.push(
      Node::Text(
        "(empty directory)",
        Style::new(fg=@color.Color::Default, dim=true),
      ),
    )
  }
  let total = browser.entries.length()
  let window_end = if browser.scroll_offset + fb_max_visible > total {
    total
  } else {
    browser.scroll_offset + fb_max_visible
  }
  for i = browser.scroll_offset; i < window_end; i = i + 1 {
    let entry = browser.entries[i]
    let icon = if entry.is_dir { "📁" } else { "📄" }
    let name_display = if entry.is_dir { entry.name + "/" } else { entry.name }
    let size_str = if entry.is_dir {
      ""
    } else {
      " (\{format_size(entry.size)})"
    }
    let marker = if i == browser.selected_idx { "▸ " } else { "  " }
    let style = if i == browser.selected_idx {
      Style::new(fg=@color.Color::Basic(@color.BasicColor::Cyan), bold=true)
    } else {
      Style::default_()
    }
    children.push(
      Node::Text("\{marker}\{icon} \{name_display}\{size_str}", style),
    )
  }
  if total > fb_max_visible {
    children.push(
      Node::Text(
        "  (\{browser.scroll_offset + 1}-\{window_end} of \{total})",
        Style::new(fg=@color.Color::Default, dim=true),
      ),
    )
  }
  if browser.show_preview && browser.preview_content.length() > 0 {
    children.push(Node::Text("", Style::default_()))
    let preview_lines = browser.preview_content.split("\n")
    let mut line_count = 0
    for line in preview_lines {
      if line_count >= 10 {
        children.push(
          Node::Text(
            "... (more lines hidden)",
            Style::new(fg=@color.Color::Default, dim=true),
          ),
        )
        break
      }
      children.push(
        Node::Text(
          "  \{line.to_string()}",
          Style::new(fg=@color.Color::Default, dim=true),
        ),
      )
      line_count = line_count + 1
    }
  }
  children.push(Node::Text("", Style::default_()))
  children.push(
    Node::Text(
      "↑↓ Navigate  Enter Open/Preview  Backspace Up Dir  Esc Back to Chat",
      Style::new(fg=@color.Color::Default, dim=true),
    ),
  )
  Node::Border(Some(title), children)
}

// ── Internal helpers ────────────────────────────────────────────────

///|
/// Join a directory path and a file name.
fn join_path(dir : String, name : String) -> String {
  if dir.has_suffix("/") {
    dir + name
  } else {
    dir + "/" + name
  }
}

///|
/// Get the parent directory path.
fn parent_path(path : String) -> String {
  if path == "/" || path == "" {
    return path
  }
  let mut trimmed = path
  while trimmed.length() > 1 && trimmed[trimmed.length() - 1] == '/' {
    trimmed = trimmed[0:trimmed.length() - 1].to_string()
  }
  let mut idx = -1
  for i = trimmed.length() - 1; i >= 0; i = i - 1 {
    if trimmed[i] == '/' {
      idx = i
      break
    }
  }
  if idx <= 0 {
    "/"
  } else {
    trimmed[0:idx].to_string()
  }
}

///|
/// Sort directory entries: directories first, then alphabetical.
fn sort_entries(entries : Array[DirEntry]) -> Unit {
  entries.sort_by(fn(a, b) {
    if a.is_dir && !b.is_dir {
      -1
    } else if !a.is_dir && b.is_dir {
      1
    } else if a.name < b.name {
      -1
    } else if a.name > b.name {
      1
    } else {
      0
    }
  })
}

///|
/// Format a file size in bytes to a human-readable string.
fn format_size(bytes : Int) -> String {
  if bytes < 1024 {
    "\{bytes}B"
  } else if bytes < 1024 * 1024 {
    "\{bytes / 1024}KB"
  } else {
    "\{bytes / (1024 * 1024)}MB"
  }
}

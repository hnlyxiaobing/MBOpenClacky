
---
name: new
description: Create a new MoonBit project to start development quickly. Use when user says "new project", "create moonbit project", "init moonbit", "新建项目", "初始化项目".
user_invocable: true
category: development
argument_hint: "[project-name] [--template &lt;template&gt;]"
allowed_tools:
  - Terminal
  - Write
  - FileReader
  - Glob
---

# Create New MoonBit Project

## Usage

When user wants to create a new project, this skill will help them scaffold it properly.

---

## Step 0: Ask Project Type and Requirements

Before doing anything, ask the user:

1. **Project name** (if not provided in the command)
2. **Project type**:
   - 📦 Library (for sharing code)
   - 🖥️ Command-line app (CLI)
   - 🌐 Web app (WASM)
   - 🔧 Mixed (library + CLI)
3. **Brief description** of what it should do

---

## Step 1: Check Directory Before Starting

Check if the current directory is empty or not:

```bash
# Check if directory is empty
ls -la
```

- If the directory is **not empty**: Ask user if they want to continue here or switch to a new directory.
- If the directory is **empty**: Continue.

---

## Step 2: Create the MoonBit Project

Use MoonBit's built-in init command:

```bash
# For a library
moon init --lib <project-name>

# For an executable (CLI)
moon init --bin <project-name>

# For both (library + CLI)
moon init <project-name>  # default creates both
```

Or manually create the structure if preferred:

```
<project-name>/
├── moon.mod              # Module definition
├── moon.pkg              # Package list
├── src/
│   ├── lib/
│   │   └── lib.mbt       # Library code
│   └── cmd/
│       └── main.mbt      # CLI entry point
└── test/
    └── hello_wbtest.mbt  # Tests
```

### moon.mod (Module Definition)

```moonbit
{
  "name": "<project-name>",
  "version": "0.1.0",
  "deps": {},
  "preferred-target": "native"
}
```

### moon.pkg (Package List)

```moonbit
{
  "packages": {
    "src/lib": {},
    "src/cmd": {},
    "test": {}
  }
}
```

---

## Step 3: Create Default Source Files

### src/lib/lib.mbt (Library)

```moonbit
pub fn hello(name: String) -> String {
  "Hello, " + name + "!"
}

test {
  @assertion.assert_eq(hello("World"), "Hello, World!")?;
}
```

### src/cmd/main.mbt (CLI)

```moonbit
fn main {
  let name = @args.args().head().or("World");
  @io.println(@lib.hello(name))
}
```

### test/hello_wbtest.mbt (Tests)

```moonbit
test "hello works" {
  @assertion.assert_eq(@lib.hello("MoonBit"), "Hello, MoonBit!")?;
}
```

---

## Step 4: Initialize Git Repository (Optional but Recommended)

Check if git is available:

```bash
git version
```

If yes:

```bash
git init
```

Create a `.gitignore` file:

```gitignore
# MoonBit build artifacts
_build/
target/

# IDE
.idea/
.vscode/
*.swp
*.swo
*~

# OS
.DS_Store
Thumbs.db
```

Create an initial commit:

```bash
git add .
git commit -m "Initial commit"
```

---

## Step 5: Create README.md

Write a good README:

```markdown
# <project-name>

<description>

## Installation

```bash
moon update && moon install
```

## Usage

```bash
moon run cmd
```

## Development

```bash
# Run tests
moon test

# Build
moon build --target native --release cmd
```

## License

MIT
```

---

## Step 6: Verify the Project Works

```bash
# Check that it builds
moon check

# Run it
moon run cmd
```

---

## Step 7: Done!

Tell the user:

```
✨ MoonBit project created successfully!

📁 Project: <project-name>
📍 Location: <directory>

🚀 Next steps:
1. cd <project-name>
2. Edit src/lib/lib.mbt to add your code
3. moon run cmd to test it
4. moon test to run tests

What would you like to build?
```

---

## Templates

Offer these pre-configured templates if the user wants something specific:

### 🔧 CLI Tool Template
Full CLI with argument parsing, commands, subcommands

### 🌐 Web App Template (WASM)
WebAssembly + JavaScript integration, browser API bindings

### 📚 Library Template
Best practices for a reusable MoonBit library

### 🎯 Minimal Template
Just the essentials, no extra stuff

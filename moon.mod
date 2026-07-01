name = "hnlyxiaobing/MBOpenClacky"

version = "0.1.0"

import {
  "moonbitlang/x@0.4.43",
  "moonbitlang/async@0.19.1",
  "bobzhang/toml@0.2.1",
  "TheWaWaR/clap@0.2.6",
  "bobzhang/crescent@0.10.0",
  "moonbit-community/tty@0.2.5",
}

repository = "https://github.com/hnlyxiaobing/MBOpenClacky"

license = "MIT"

keywords = [ "ai", "agent", "cli", "llm" ]

description = "AI Agent CLI tool rewritten in MoonBit"

preferred_target = "native"

// native link flags are platform-specific:
//   Windows: bcrypt.lib / winhttp.lib via #pragma comment(lib,...) in C sources
//   Linux/macOS: uncomment cc-link-flags in lib/brand/moon.pkg and lib/client/moon.pkg

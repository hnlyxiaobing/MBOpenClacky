name = "hnlyxiaobing/MBOpenClacky"

version = "0.1.0"

readme = "README.md"

import {
  "moonbitlang/x@0.4.50",
  "moonbitlang/async@0.20.5",
  "hnlyxiaobing/toml@0.4.6",
  "TheWaWaR/clap@0.2.6",
  "hnlyxiaobing/crescent@0.10.2",
  "moonbit-community/tty@0.3.0",
  "moonbit-community/pty@0.4.0",
  "mizchi/tui@0.10.0",
  "mizchi/signals@0.6.5",
  "hustcer/tabular@0.5.2",
}

repository = "https://github.com/hnlyxiaobing/MBOpenClacky"

license = "MIT"

keywords = [ "ai", "agent", "cli", "llm" ]

description = "AI Agent CLI tool rewritten in MoonBit"

preferred_target = "native"

options(
  exclude: [ ],
  "--moonbit-unstable-prebuild": "build-script.js",
)

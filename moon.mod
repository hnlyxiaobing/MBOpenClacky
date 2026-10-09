name = "hnlyxiaobing/MBOpenClacky"

version = "0.2.0"

readme = "README.md"

import {
  "moonbitlang/x@0.5.5",
  "moonbitlang/async@0.22.4",
  "moonbit-community/toml@0.5.0",
  "DzmingLi/clap@0.2.8",
  "hnlyxiaobing/crescent@0.10.7",
  "hnlyxiaobing/moonbitmark@0.4.5",
  "moonbit-community/tty@0.4.0",
  "moonbit-community/pty@0.4.3",
  "mizchi/tui@0.10.2",
  "mizchi/signals@0.6.6",
  "hustcer/tabular@0.6.0",
}

repository = "https://github.com/hnlyxiaobing/MBOpenClacky"

license = "MIT"

keywords = [ "ai", "agent", "cli", "llm" ]

description = "AI Agent CLI tool rewritten in MoonBit"

preferred_target = "native"

options(
  "--moonbit-unstable-prebuild": "scripts/build-script.js",
)

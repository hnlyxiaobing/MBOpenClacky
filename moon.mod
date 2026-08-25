name = "hnlyxiaobing/MBOpenClacky"

version = "0.1.1"

readme = "README.md"

import {
  "moonbitlang/x@0.5.1",
  "moonbitlang/async@0.21.0",
  "hnlyxiaobing/toml@0.4.8",
  "TheWaWaR/clap@0.2.6",
  "hnlyxiaobing/crescent@0.10.5",
  "hnlyxiaobing/moonbitmark@0.4.2",
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

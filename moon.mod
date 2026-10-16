name = "hnlyxiaobing/MBOpenClacky"

version = "0.3.1"

readme = "README.md"

import {
  "moonbitlang/x@0.5.5",
  "moonbitlang/async@0.22.5",
  "moonbit-community/toml@0.5.0",
  "hnlyxiaobing/crescent@0.10.7",
  "hnlyxiaobing/moonbitmark@0.5.0",
  "moonbit-community/tty@0.5.0",
  "moonbit-community/pty@0.4.3",
  "mizchi/signals@0.6.6",
  "hustcer/tabular@0.6.0",
  "moonbit-community/unicodewidth@0.2.1",
}

repository = "https://github.com/hnlyxiaobing/MBOpenClacky"

license = "MIT"

keywords = [ "ai", "agent", "cli", "llm" ]

description = "AI Agent CLI tool rewritten in MoonBit"

preferred_target = "native"

options(
  "--moonbit-unstable-prebuild": "scripts/build-script.js",
)

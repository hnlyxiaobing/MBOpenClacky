name = "hnlyxiaobing/MBOpenClacky"

version = "0.3.3"

readme = "README.md"

import {
  "moonbitlang/x@0.5.7",
  "moonbitlang/async@0.22.7",
  "moonbit-community/toml@0.5.1",
  "hnlyxiaobing/crescent@0.10.8",
  "hnlyxiaobing/moonbitmark@0.5.1",
  "moonbit-community/tty@0.6.2",
  "moonbit-community/pty@0.4.4",
  "mizchi/signals@0.6.6",
  "hustcer/tabular@0.6.0",
  "moonbit-community/unicodewidth@0.2.1",
  "bobzhang/lexer@0.3.1",
}

repository = "https://github.com/hnlyxiaobing/MBOpenClacky"

license = "MIT"

keywords = [ "ai", "agent", "cli", "llm" ]

description = "AI Agent CLI tool rewritten in MoonBit"

preferred_target = "native"

options(
  "--moonbit-unstable-prebuild": "scripts/build-script.js",
)

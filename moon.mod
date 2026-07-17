name = "hnlyxiaobing/MBOpenClacky"

version = "0.1.0"

readme = "README.md"

import {
  "moonbitlang/x@0.4.43",
  "moonbitlang/async@0.20.2",
  "hnlyxiaobing/toml@0.4.2",
  "TheWaWaR/clap@0.2.6",
  "hnlyxiaobing/crescent@0.10.1",
  "moonbit-community/tty@0.3.0",
}

repository = "https://github.com/hnlyxiaobing/MBOpenClacky"

license = "MIT"

keywords = [ "ai", "agent", "cli", "llm" ]

description = "AI Agent CLI tool rewritten in MoonBit"

preferred_target = "native"

options(
  exclude: [ "web/mb" ],
)

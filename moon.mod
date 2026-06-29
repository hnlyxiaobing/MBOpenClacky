name = "hnlyxiaobing/MBOpenClacky"

version = "0.1.0"

import {
  "moonbitlang/x@0.4.43",
  "moonbitlang/async@0.19.1",
  "bobzhang/toml@0.2.1",
  "TheWaWaR/clap@0.2.6",
  "Frank-III/onebit-tui@0.1.3",
  "bobzhang/crescent@0.10.0",
}

repository = "https://github.com/hnlyxiaobing/MBOpenClacky"

license = "MIT"

keywords = [ "ai", "agent", "cli", "llm" ]

description = "AI Agent CLI tool rewritten in MoonBit"

options(
  link: { "native": { "cc": "-lcurl -lssl -lcrypto" } },
)

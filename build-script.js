#!/usr/bin/env node
// MBOpenClacky 构建预配置脚本（moon.mod --moonbit-unstable-prebuild 入口）。
//
// 用途：
//   新构建规划器（moonbuild-rupes-recta，moon 0.1.20260807）把 moon.pkg 中
//   带 `link` 选项的包一律当作可执行目标（MakeExecutable）链接——见
//   crates/moonbuild-rupes-recta/src/intent.rs 的 is_linkable()：
//     pkg.raw.force_link || pkg.raw.link.is_some() || pkg.raw.is_main
//   而纯库包没有 fn main，链接必然报 `undefined reference to main`。
//
//   因此 lib/brand、lib/web 不能再在自己的 moon.pkg 里声明
//   `link: { native: { cc-link-flags: "-lcrypto" } }`（它同时触发 Source
//   目标的可执行文件生成）。但它们的 whitebox 测试可执行文件链接时仍需要
//   -lcrypto（crypto_native.c 引用 OpenSSL EVP_*/RAND_bytes 符号）。
//
//   本脚本通过 moon 的 pre-build 链接配置机制（propagate_link_config，
//   见 crates/moonbuild-rupes-recta/src/build_lower/lower_build.rs 与
//   build_plan/builders.rs）为 lib/brand、lib/web 提供 `-lcrypto`，
//   该配置只影响链接阶段，不会触发可执行文件生成。
//
// 输入（stdin）：BuildScriptEnvironment JSON（env / paths）
// 输出（stdout）：BuildScriptOutput JSON（rerun_if / vars / link_configs）
'use strict';

const MODULE_NAME = 'hnlyxiaobing/MBOpenClacky';
// cmd is the main executable; lib/brand & lib/web whitebox test executables
// also link against libcrypto via their test artifacts.
const CRYPTO_PKGS = ['cmd', 'lib/brand', 'lib/web'];

let input = '';
process.stdin.on('data', (chunk) => {
  input += chunk;
});
process.stdin.on('end', () => {
  // Windows uses BCrypt/CNG (auto-linked via #pragma comment in
  // crypto_native.c), so -lcrypto must NOT be injected there: MSVC would
  // search for crypto.lib (unavailable without an OpenSSL install) and
  // fail with LNK1181. Only Linux/macOS need the OpenSSL link.
  const isWindows = process.platform === 'win32';
  const output = {
    rerun_if: [],
    vars: {},
    link_configs: isWindows ? [] : CRYPTO_PKGS.map((pkg) => ({
      package: `${MODULE_NAME}/${pkg}`,
      link_flags: null,
      link_libs: ['crypto'],
      link_search_paths: [],
    })),
  };
  process.stdout.write(JSON.stringify(output));
});

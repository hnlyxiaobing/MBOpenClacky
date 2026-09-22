#!/usr/bin/env node
// MBOpenClacky 构建预配置脚本（moon.mod 的 "--moonbit-unstable-prebuild" 入口）。
//
// 为什么需要它：新构建规划器（moonbuild-rupes-recta）把 moon.pkg 中带 `link`
// 选项的包一律当作可执行目标链接（见 intent.rs 的 is_linkable()：
// pkg.raw.force_link || pkg.raw.link.is_some() || pkg.raw.is_main），而纯库包
// 没有 fn main，链接必然报 `undefined reference to main`。
//
// 因此 lib/brand、lib/web 不能在各自的 moon.pkg 里声明 -lcrypto，但它们的
// whitebox 测试可执行文件链接时仍需要（crypto_native.c 引用 OpenSSL
// EVP_*/RAND_bytes）。本脚本经 moon 的 pre-build 链接配置机制注入 -lcrypto，
// 该配置只作用于链接阶段，不触发可执行文件生成。
//
// 输入（stdin）：BuildScriptEnvironment JSON（本脚本不解析，仅排空）
// 输出（stdout）：BuildScriptOutput JSON（rerun_if / vars / link_configs）
'use strict';

const MODULE_NAME = 'hnlyxiaobing/MBOpenClacky';
// cmd 是主可执行文件；lib/brand & lib/web 的 whitebox 测试可执行文件
// 也要经各自的测试制品链接 libcrypto。
const CRYPTO_PKGS = ['cmd', 'lib/brand', 'lib/web'];

process.stdin.on('data', () => {});
process.stdin.on('end', () => {
  // Windows 走 BCrypt/CNG（由 crypto_native.c 的 #pragma comment 自动链接），
  // 因此不能注入 -lcrypto：MSVC 会去找 crypto.lib（无 OpenSSL 安装时不存在）
  // 并以 LNK1181 失败。只有 Linux/macOS 需要 OpenSSL 链接。
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
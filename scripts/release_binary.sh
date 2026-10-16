#!/bin/sh
# Echo the path of the release `cmd` binary.
#
# moon's output layout depends on the workspace: while vendor/* were extra
# members it wrote _build/native/release/build/<owner>/<module>/cmd/cmd, and a
# release tree can still hold a stale artifact from that layout after they were
# removed. Check the current (package-relative) layout first so a stale nested
# copy can never be mistaken for the fresh one.
#
# Arg 1 is the *build tree* root (…/_build/native/release/build), not the repo
# root — call it with no argument from the repo root.
set -eu

ROOT=${1:-_build/native/release/build}

for base in "$ROOT/cmd" "$ROOT/hnlyxiaobing/MBOpenClacky/cmd"; do
  for name in cmd cmd.exe; do
    if [ -x "$base/$name" ]; then
      echo "$base/$name"
      exit 0
    fi
  done
done

echo "release binary not found under $ROOT" >&2
exit 1

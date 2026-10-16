#!/bin/sh
# Build the MBOpenClacky release binary inside Docker.
#
# The current MoonBit toolchain rejects legacy moon.mod.json / moon.pkg.json
# descriptors, but registry dependencies are downloaded lazily during
# `moon build`.  This wrapper builds in a loop: when moon aborts because of a
# legacy descriptor, we migrate every downloaded legacy file and retry, until
# the build either succeeds or fails for a non-legacy reason.

set -eu

cd /build

attempt=0
max_attempts=20

while [ $attempt -lt $max_attempts ]; do
  attempt=$((attempt + 1))
  echo "moon build attempt $attempt/$max_attempts"

  if moon build --target native --release cmd > /tmp/moon_build.log 2>&1; then
    echo "moon build succeeded"
    break
  fi

  if grep -q 'is no longer supported. Run `moon fmt` to migrate' /tmp/moon_build.log; then
    echo "legacy descriptor detected; running migration"
    bash scripts/migrate_moon_mod_json.sh
  else
    echo "moon build failed with non-legacy error:"
    cat /tmp/moon_build.log
    exit 1
  fi

  if [ $attempt -eq $max_attempts ]; then
    echo "exceeded maximum build attempts"
    cat /tmp/moon_build.log
    exit 1
  fi
done

BIN=$(bash scripts/release_binary.sh /build/_build/native/release/build)
mkdir -p /build/out
cp "$BIN" /build/out/mbopenclacky
test -x /build/out/mbopenclacky
echo "release binary ready: $BIN"

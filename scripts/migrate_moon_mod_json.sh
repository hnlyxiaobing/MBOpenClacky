#!/bin/sh
# Migrate legacy moon.mod.json / moon.pkg.json files in .mooncakes to moon.mod / moon.pkg.
# The MoonBit toolchain no longer accepts the .json module/package descriptors for
# dependencies downloaded from the registry. Running `moon fmt` from inside the
# directory that contains the legacy file converts it in place.

set -eu

count_file="$(mktemp)"
trap 'rm -f "$count_file"' EXIT

# Migrate legacy module descriptors.
find .mooncakes -name moon.mod.json -print0 2>/dev/null | while IFS= read -r -d '' json_path; do
  module_dir="$(dirname "$json_path")"
  echo "Migrating legacy moon.mod.json -> moon.mod in $module_dir"
  (cd "$module_dir" && moon fmt)
  # Increment counter in temp file so the value survives the pipeline subshell.
  printf '%s' '+' >> "$count_file"
done

# Migrate legacy package descriptors.
find .mooncakes -name moon.pkg.json -print0 2>/dev/null | while IFS= read -r -d '' json_path; do
  pkg_dir="$(dirname "$json_path")"
  echo "Migrating legacy moon.pkg.json -> moon.pkg in $pkg_dir"
  (cd "$pkg_dir" && moon fmt)
  printf '%s' '+' >> "$count_file"
done

changed="$(wc -c < "$count_file" | tr -d ' ')"
echo "Migrated ${changed} legacy descriptor(s)."

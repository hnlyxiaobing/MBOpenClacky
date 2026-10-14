#!/bin/sh
# Migrate legacy moon.mod.json files in .mooncakes to moon.mod.
# The MoonBit toolchain no longer accepts moon.mod.json for dependencies
# downloaded from the registry. Running `moon fmt` from inside the module
# directory converts the file in place.

set -eu

count_file="$(mktemp)"
trap 'rm -f "$count_file"' EXIT

find .mooncakes -name moon.mod.json -print0 2>/dev/null | while IFS= read -r -d '' json_path; do
  module_dir="$(dirname "$json_path")"
  echo "Migrating legacy moon.mod.json -> moon.mod in $module_dir"
  (cd "$module_dir" && moon fmt)
  # Increment counter in temp file so the value survives the pipeline subshell.
  printf '%s' '+' >> "$count_file"
done

changed="$(wc -c < "$count_file" | tr -d ' ')"
echo "Migrated ${changed} legacy module descriptor(s)."

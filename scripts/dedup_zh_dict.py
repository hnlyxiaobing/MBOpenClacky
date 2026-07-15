#!/usr/bin/env python3
# Remove duplicate keys from Chinese dictionary

import re

with open('web/mb/main/i18n_dict_zh.mbt', 'r', encoding='utf-8') as f:
    lines = f.readlines()

# Extract all key-value pairs
pattern = r'\("([^"]+)",\s*"([^"]*)"\)'
seen_keys = {}
new_lines = []
duplicate_count = 0

for line in lines:
    match = re.search(pattern, line)
    if match:
        key = match.group(1)
        if key in seen_keys:
            duplicate_count += 1
            continue  # Skip duplicate
        seen_keys[key] = True
    new_lines.append(line)

# Write the deduplicated dictionary
with open('web/mb/main/i18n_dict_zh.mbt', 'w', encoding='utf-8') as f:
    f.writelines(new_lines)

print(f"Removed {duplicate_count} duplicate keys")
print(f"New dictionary has {len(new_lines)} lines")
print(f"Unique keys: {len(seen_keys)}")
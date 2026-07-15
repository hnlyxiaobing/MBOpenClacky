#!/usr/bin/env python3
# Check Chinese dictionary keys

import re

# Read English dictionary
with open('web/mb/main/i18n_dict_en.mbt', 'r', encoding='utf-8') as f:
    en_content = f.read()

# Read Chinese dictionary
with open('web/mb/main/i18n_dict_zh.mbt', 'r', encoding='utf-8') as f:
    zh_content = f.read()

# Extract keys
pattern = r'\("([^"]+)",\s*"[^"]*"\)'
en_keys = set(re.findall(pattern, en_content))
zh_keys = set(re.findall(pattern, zh_content))

print(f"English dictionary keys: {len(en_keys)}")
print(f"Chinese dictionary keys: {len(zh_keys)}")
print(f"Missing from Chinese: {len(en_keys - zh_keys)}")
print(f"Missing from English: {len(zh_keys - en_keys)}")
print(f"Common keys: {len(en_keys & zh_keys)}")

# Show first 10 missing keys
missing = sorted(en_keys - zh_keys)
print(f"\nFirst 10 missing from Chinese:")
for key in missing[:10]:
    print(f"  {key}")
#!/usr/bin/env python3
# Verify translation coverage - check if all code keys are in dictionary

import re
import os

# Read dictionaries
with open('web/mb/main/i18n_dict_en.mbt', 'r', encoding='utf-8') as f:
    en_content = f.read()

with open('web/mb/main/i18n_dict_zh.mbt', 'r', encoding='utf-8') as f:
    zh_content = f.read()

# Extract dictionary keys
pattern = r'\("([^"]+)",\s*"[^"]*"\)'
en_keys = set(re.findall(pattern, en_content))
zh_keys = set(re.findall(pattern, zh_content))

print(f"English dictionary keys: {len(en_keys)}")
print(f"Chinese dictionary keys: {len(zh_keys)}")

# Scan code files for translation keys
code_keys = set()
code_dir = 'web/mb/main'
for filename in os.listdir(code_dir):
    if filename.endswith('.mbt'):
        filepath = os.path.join(code_dir, filename)
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
        
        # Find t("key") calls
        t_pattern = r'(?:^|[\s(,=])t\("([^"]+)"\)'
        t_matches = re.findall(t_pattern, content)
        
        # Find t1("key", ...) calls
        t1_pattern = r'(?:^|[\s(,=])t1\("([^"]+)",'
        t1_matches = re.findall(t1_pattern, content)
        
        # Filter to valid translation keys (must have dot)
        for key in t_matches + t1_matches:
            if '.' in key and not key.startswith('/'):
                code_keys.add(key)

print(f"\nCode keys found: {len(code_keys)}")

# Check coverage
missing_in_en = code_keys - en_keys
missing_in_zh = code_keys - zh_keys

print(f"\nMissing from English dictionary: {len(missing_in_en)}")
for key in sorted(missing_in_en)[:10]:
    print(f"  {key}")

print(f"\nMissing from Chinese dictionary: {len(missing_in_zh)}")
for key in sorted(missing_in_zh)[:10]:
    print(f"  {key}")

# Check extra keys (in dictionary but not in code)
extra_in_en = en_keys - code_keys
extra_in_zh = zh_keys - code_keys

print(f"\nExtra keys in English dictionary: {len(extra_in_en)}")
print(f"Extra keys in Chinese dictionary: {len(extra_in_zh)}")

# Calculate coverage
coverage_en = len(code_keys - missing_in_en) / len(code_keys) * 100 if code_keys else 100
coverage_zh = len(code_keys - missing_in_zh) / len(code_keys) * 100 if code_keys else 100

print(f"\nTranslation coverage:")
print(f"  English: {coverage_en:.1f}%")
print(f"  Chinese: {coverage_zh:.1f}%")
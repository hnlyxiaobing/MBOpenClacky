# Script to extract i18n translation keys from code and dictionary
# Uses more precise regex to match only t("key") and t1("key", ...) calls

Write-Host "=== i18n Key Extraction Script ===" -ForegroundColor Cyan

# Step 1: Extract keys from dictionary files
Write-Host "`n1. Extracting keys from dictionary files..." -ForegroundColor Yellow

$en_dict_path = "web\mb\main\i18n_dict_en.mbt"
$zh_dict_path = "web\mb\main\i18n_dict_zh.mbt"

# Function to extract keys from dictionary file
function Extract-DictKeys($file_path) {
    if (-not (Test-Path $file_path)) {
        Write-Host "File not found: $file_path" -ForegroundColor Red
        return @()
    }
    
    $content = Get-Content $file_path -Raw
    $pattern = '\("([^"]+)",\s*"[^"]*"\)'
    $matches = [regex]::Matches($content, $pattern)
    
    $keys = @()
    foreach ($match in $matches) {
        $keys += $match.Groups[1].Value
    }
    
    return $keys
}

$en_keys = Extract-DictKeys $en_dict_path
$zh_keys = Extract-DictKeys $zh_dict_path

Write-Host "English dictionary keys: $($en_keys.Count)" -ForegroundColor Green
Write-Host "Chinese dictionary keys: $($zh_keys.Count)" -ForegroundColor Green

# Step 2: Extract translation keys from code files
Write-Host "`n2. Extracting translation keys from code files..." -ForegroundColor Yellow

$code_files = Get-ChildItem -Path "web\mb\main" -Filter "*.mbt" -Recurse
$code_keys = @()

foreach ($file in $code_files) {
    $content = Get-Content $file.FullName -Raw
    
    # Pattern for t("key") calls
    $t_pattern = '(?:^|[\s(,=])t\("([^"]+)"\)'
    $t_matches = [regex]::Matches($content, $t_pattern)
    
    # Pattern for t1("key", ...) calls
    $t1_pattern = '(?:^|[\s(,=])t1\("([^"]+)",'
    $t1_matches = [regex]::Matches($content, $t1_pattern)
    
    foreach ($match in $t_matches) {
        $key = $match.Groups[1].Value
        # Filter out non-translation keys (API paths, variable names, etc.)
        if ($key -match '^[a-z_]+\.[a-z_]+$') {
            $code_keys += $key
        }
    }
    
    foreach ($match in $t1_matches) {
        $key = $match.Groups[1].Value
        # Filter out non-translation keys
        if ($key -match '^[a-z_]+\.[a-z_]+$') {
            $code_keys += $key
        }
    }
}

$code_keys = $code_keys | Sort-Object -Unique
Write-Host "Unique translation keys found in code: $($code_keys.Count)" -ForegroundColor Green

# Step 3: Find missing keys (in code but not in dictionary)
Write-Host "`n3. Finding missing keys..." -ForegroundColor Yellow

$missing_in_en = @()
$missing_in_zh = @()

foreach ($key in $code_keys) {
    if ($key -notin $en_keys) {
        $missing_in_en += $key
    }
    if ($key -notin $zh_keys) {
        $missing_in_zh += $key
    }
}

Write-Host "Keys missing from English dictionary: $($missing_in_en.Count)" -ForegroundColor Red
Write-Host "Keys missing from Chinese dictionary: $($missing_in_zh.Count)" -ForegroundColor Red

# Step 4: Find extra keys (in dictionary but not in code)
Write-Host "`n4. Finding extra keys..." -ForegroundColor Yellow

$extra_in_en = @()
$extra_in_zh = @()

foreach ($key in $en_keys) {
    if ($key -notin $code_keys) {
        $extra_in_en += $key
    }
}

foreach ($key in $zh_keys) {
    if ($key -notin $code_keys) {
        $extra_in_zh += $key
    }
}

Write-Host "Extra keys in English dictionary: $($extra_in_en.Count)" -ForegroundColor Blue
Write-Host "Extra keys in Chinese dictionary: $($extra_in_zh.Count)" -ForegroundColor Blue

# Step 5: Find asymmetry between dictionaries
Write-Host "`n5. Checking dictionary asymmetry..." -ForegroundColor Yellow

$en_only = @()
$zh_only = @()

foreach ($key in $en_keys) {
    if ($key -notin $zh_keys) {
        $en_only += $key
    }
}

foreach ($key in $zh_keys) {
    if ($key -notin $en_keys) {
        $zh_only += $key
    }
}

Write-Host "Keys only in English: $($en_only.Count)" -ForegroundColor Magenta
Write-Host "Keys only in Chinese: $($zh_only.Count)" -ForegroundColor Magenta

# Step 6: Group missing keys by prefix
Write-Host "`n6. Grouping missing keys by prefix..." -ForegroundColor Yellow

$missing_keys = $missing_in_en + $missing_in_zh | Sort-Object -Unique
$grouped = @{}

foreach ($key in $missing_keys) {
    $prefix = $key.Split('.')[0]
    if (-not $grouped.ContainsKey($prefix)) {
        $grouped[$prefix] = @()
    }
    $grouped[$prefix] += $key
}

foreach ($group in $grouped.GetEnumerator() | Sort-Object Name) {
    Write-Host "$($group.Key): $($group.Value.Count) keys" -ForegroundColor Cyan
}

# Step 7: Save results to files
Write-Host "`n7. Saving results..." -ForegroundColor Yellow

# Save missing keys
$missing_keys | Out-File -FilePath "missing_keys_clean.txt" -Encoding UTF8
Write-Host "Saved missing keys to missing_keys_clean.txt" -ForegroundColor Green

# Save extra keys
$extra_in_en | Out-File -FilePath "extra_keys_en.txt" -Encoding UTF8
$extra_in_zh | Out-File -FilePath "extra_keys_zh.txt" -Encoding UTF8
Write-Host "Saved extra keys to extra_keys_en.txt and extra_keys_zh.txt" -ForegroundColor Green

# Save asymmetry
$en_only | Out-File -FilePath "en_only_keys.txt" -Encoding UTF8
$zh_only | Out-File -FilePath "zh_only_keys.txt" -Encoding UTF8
Write-Host "Saved asymmetric keys to en_only_keys.txt and zh_only_keys.txt" -ForegroundColor Green

# Summary
Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "Total code keys: $($code_keys.Count)" -ForegroundColor White
Write-Host "Total English keys: $($en_keys.Count)" -ForegroundColor White
Write-Host "Total Chinese keys: $($zh_keys.Count)" -ForegroundColor White
Write-Host "Missing from English: $($missing_in_en.Count)" -ForegroundColor White
Write-Host "Missing from Chinese: $($missing_in_zh.Count)" -ForegroundColor White
Write-Host "Extra in English: $($extra_in_en.Count)" -ForegroundColor White
Write-Host "Extra in Chinese: $($extra_in_zh.Count)" -ForegroundColor White
Write-Host "English only: $($en_only.Count)" -ForegroundColor White
Write-Host "Chinese only: $($zh_only.Count)" -ForegroundColor White

Write-Host "`n=== Next Steps ===" -ForegroundColor Cyan
Write-Host "1. Review missing_keys_clean.txt for keys that need translation" -ForegroundColor White
Write-Host "2. Review en_only_keys.txt and zh_only_keys.txt for dictionary asymmetry" -ForegroundColor White
Write-Host "3. Start with sessions group (most missing keys)" -ForegroundColor White
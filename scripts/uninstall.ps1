#Requires -Version 5.1
<#
.SYNOPSIS
    MBOpenClacky uninstaller for Windows.
.DESCRIPTION
    Removes the installed binary. User data under
    $env:USERPROFILE\.mbopenclacky is preserved unless -Purge is given.
.PARAMETER Purge
    Also remove the config/data directory (~\.mbopenclacky).
.PARAMETER Yes
    Non-interactive: do not prompt for confirmation.
#>
param(
    [switch]$Purge,
    [switch]$Yes
)

$ErrorActionPreference = "Stop"
$BinName = "mbopenclacky.exe"
# The binary is typically installed under the user's local tools dir.
$Candidates = @(
    "$env:LOCALAPPDATA\MBOpenClacky\$BinName",
    "$env:LOCALAPPDATA\Programs\MBOpenClacky\$BinName",
    (Join-Path $PSScriptRoot "..\mbopenclacky.exe")
)

function Confirm-Action($msg) {
    if ($Yes) { return $true }
    $answer = Read-Host "$msg [y/N]"
    return ($answer -match '^(y|yes)$')
}

Write-Host "`n>> Removing MBOpenClacky binary..." -ForegroundColor Cyan

$removed = $false
foreach ($bin in $Candidates) {
    $resolved = Resolve-Path -Path $bin -ErrorAction SilentlyContinue
    if ($resolved) {
        if (Confirm-Action "Remove $($resolved.Path)?") {
            Remove-Item -Force -Path $resolved.Path
            Write-Host "  [OK] Removed $($resolved.Path)" -ForegroundColor Green
            $removed = $true
        } else {
            Write-Host "  [!] Skipped $($resolved.Path)" -ForegroundColor Yellow
        }
    }
}
if (-not $removed) {
    Write-Host "  [OK] No binary found at candidate locations." -ForegroundColor Green
}

if ($Purge) {
    Write-Host "`n>> Purging user data (--Purge requested)..." -ForegroundColor Cyan
    $dataDir = Join-Path $env:USERPROFILE ".mbopenclacky"
    if (Test-Path $dataDir) {
        if (Confirm-Action "PERMANENTLY remove $dataDir (config, sessions, skills, logs, memory)?") {
            Remove-Item -Recurse -Force -Path $dataDir
            Write-Host "  [OK] Removed $dataDir" -ForegroundColor Green
        } else {
            Write-Host "  [!] Skipped data purge; $dataDir kept." -ForegroundColor Yellow
        }
    } else {
        Write-Host "  [OK] No data directory at $dataDir." -ForegroundColor Green
    }
} else {
    Write-Host "`n>> Keeping user data at ~\.mbopenclacky (use -Purge to remove)." -ForegroundColor Cyan
}

Write-Host "`n=============================================" -ForegroundColor Magenta
Write-Host "  MBOpenClacky uninstalled." -ForegroundColor Magenta
Write-Host "=============================================" -ForegroundColor Magenta

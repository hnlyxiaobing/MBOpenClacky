#Requires -Version 5.1
<#
.SYNOPSIS
    MBOpenClacky installation script for Windows.
.DESCRIPTION
    Checks prerequisites, installs dependencies, builds the project,
    and prints configuration guidance.
.NOTES
    Run from the project root directory or pass -ProjectRoot.
.PARAMETER ProjectRoot
    Path to the project root directory.
.PARAMETER AutoInstall
    Non-interactive mode: auto-install MoonBit if missing (CI/CD friendly).
.PARAMETER Target
    Override build target (native/wasm-gc).
#>

param(
    # Script now lives in scripts/; default ProjectRoot is the repo root (one level up)
    [string]$ProjectRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Definition)),
    [switch]$AutoInstall,
    [string]$Target = ""
)

$ErrorActionPreference = "Stop"

# ── Helpers ─────────────────────────────────────────────────────────────────

function Write-Step($msg) {
    Write-Host "`n>> $msg" -ForegroundColor Cyan
}

function Write-OK($msg) {
    Write-Host "  [OK] $msg" -ForegroundColor Green
}

function Write-Warn($msg) {
    Write-Host "  [!] $msg" -ForegroundColor Yellow
}

function Write-Err($msg) {
    Write-Host "  [ERROR] $msg" -ForegroundColor Red
}

# ── Utility functions ────────────────────────────────────────────────────────

function Add-ToUserPath {
    param([string]$Dir)
    $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $entries = $currentPath -split ';' | Where-Object { $_ -ne '' }
    if ($entries -notcontains $Dir) {
        $newPath = ($entries + $Dir) -join ';'
        [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        Write-OK "Added $Dir to user PATH"
    }
}

# Import a vcvarsall.bat environment into this process and re-look for cl.exe.
# Returns the cl.exe command, or $null when no usable MSVC install was found.
function Activate-Msvc {
    $candidates = @()
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vswhere) {
        $vsPath = & $vswhere -latest -property installationPath 2>$null
        if ($vsPath) {
            $candidates += (Join-Path $vsPath "VC\Auxiliary\Build\vcvarsall.bat")
        }
    }
    # Fallback for installs that vswhere cannot see.
    foreach ($edition in "Community", "Professional", "Enterprise") {
        $candidates += "$env:ProgramFiles\Microsoft Visual Studio\2022\$edition\VC\Auxiliary\Build\vcvarsall.bat"
        $candidates += "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\$edition\VC\Auxiliary\Build\vcvarsall.bat"
    }
    foreach ($vcvarsall in $candidates) {
        if (-not (Test-Path $vcvarsall)) { continue }
        Write-Host "  Activating MSVC via $vcvarsall x64..." -ForegroundColor Gray
        cmd /c "`"$vcvarsall`" x64 >nul 2>&1 && set" | ForEach-Object {
            if ($_ -match "^(.+?)=(.*)$") {
                [Environment]::SetEnvironmentVariable($matches[1], $matches[2], "Process")
            }
        }
        $cl = Get-Command cl.exe -ErrorAction SilentlyContinue
        if ($cl) {
            Write-OK "cl.exe activated: $($cl.Source)"
            return $cl
        }
    }
    return $null
}

function Install-MoonBit {
    Write-Step "Installing MoonBit toolchain..."
    try {
        Invoke-Expression (Invoke-WebRequest -Uri "https://cli.moonbitlang.com/install/powershell.ps1" -UseBasicParsing).Content
        Add-ToUserPath "$env:USERPROFILE\.moon\bin"
        $env:Path = "$env:USERPROFILE\.moon\bin;$env:Path"
        Write-OK "MoonBit installed successfully."
    } catch {
        Write-Err "Failed to install MoonBit: $_"
        Write-Host "  Please install manually from https://www.moonbitlang.com/download/"
        exit 1
    }
}

# ── Step 1: Check moon ──────────────────────────────────────────────────────

Write-Step "Checking MoonBit toolchain..."

$moonCmd = Get-Command moon -ErrorAction SilentlyContinue
if (-not $moonCmd) {
    if ($AutoInstall) {
        Write-Warn "moon command not found, auto-installing..."
        Install-MoonBit
        $moonCmd = Get-Command moon -ErrorAction SilentlyContinue
        if (-not $moonCmd) {
            Write-Err "MoonBit installation completed but moon is still not in PATH."
            Write-Host "  Please restart your terminal and re-run this script."
            exit 1
        }
    } else {
        Write-Err "moon command not found."
        Write-Host "  Please install MoonBit from https://www.moonbitlang.com/download/"
        Write-Host "  Then add it to PATH and re-run this script."
        Write-Host ""
        Write-Host "  Or re-run with -AutoInstall to install automatically:"
        Write-Host "    .\scripts\install.ps1 -AutoInstall"
        exit 1
    }
}

$moonVersion = (moon version 2>&1) -join " "
Write-OK "moon found: $moonVersion"

# ── Step 2: Check C compiler ────────────────────────────────────────────────

Write-Step "Checking C compiler (cl.exe)..."

$clCmd = Get-Command cl.exe -ErrorAction SilentlyContinue
if ($clCmd) {
    Write-OK "cl.exe found: $($clCmd.Source)"
} else {
    Write-Warn "cl.exe not found in PATH. Attempting to activate MSVC environment..."
    $clCmd = Activate-Msvc
}

if ($clCmd) {
    $hasCC = $true
} else {
    Write-Host "  Native builds require MSVC Build Tools." -ForegroundColor Yellow
    Write-Host "  Download from: https://visualstudio.microsoft.com/visual-cpp-build-tools/"
    Write-Host "  Or open 'x64 Native Tools Command Prompt' and re-run this script."
    Write-Host "  You can still build for wasm-gc without a C compiler."
    $hasCC = $false
}

# ── Step 3: Update & install dependencies ───────────────────────────────────

Write-Step "Updating MoonBit package index..."

Set-Location $ProjectRoot
moon update
if ($LASTEXITCODE -ne 0) {
    Write-Err "moon update failed (exit code: $LASTEXITCODE)"
    exit 1
}
Write-OK "Package index updated. Dependencies are resolved by moon update / build."

# Note: bare `moon install` is deprecated and exits non-zero on the
# 2026-09+ toolchains; `moon update` already downloads all dependencies.

# ── Step 4: Build ────────────────────────────────────────────────────────────

# Determine build target: user override > auto-detect
if ($Target -ne "") {
    $buildTarget = $Target
    Write-OK "Using user-specified target: $buildTarget"
} else {
    $buildTarget = if ($hasCC) { "native" } else { "wasm-gc" }
}
Write-Step "Building project (target: $buildTarget)..."

# `cmd` is named explicitly and the build is a release one: a bare `moon build`
# walks the whole moon.work workspace (whose vendored member has a test driver
# that ICEs), and verifying _build/.../release after a debug build finds nothing.
moon build --target $buildTarget --release cmd
if ($LASTEXITCODE -ne 0) {
    Write-Err "moon build failed (exit code: $LASTEXITCODE)"
    Write-Host "  Run 'moon check' for detailed error information."
    exit 1
}
Write-OK "Build succeeded."

# ── Step 5: Verify build artifacts ──────────────────────────────────────────

Write-Step "Verifying build artifacts..."

# The release tree is keyed by author/module, so search it instead of
# hard-coding a path that the layout has already outgrown.
$buildRoot = Join-Path $ProjectRoot "_build\$buildTarget\release\build"
$found = $null
if ($buildTarget -eq "native") {
    $found = Get-ChildItem -Path $buildRoot -Recurse -Filter "cmd.exe" -ErrorAction SilentlyContinue
    if ($found) {
        Write-OK "Build artifact(s) found:"
        $found | ForEach-Object { Write-Host "  $($_.FullName)" -ForegroundColor Gray }
    } else {
        Write-Warn "No cmd.exe under $buildRoot"
        Write-Host "  The build succeeded but no executable was produced."
        Write-Host "  Check that cmd/main.mbt contains a main() entry point."
    }
} else {
    $wasm = @(Get-ChildItem -Path $buildRoot -Recurse -Filter "*.wasm" -ErrorAction SilentlyContinue)
    Write-OK "wasm-gc artifacts: $($wasm.Count) file(s) under $buildRoot"
}

# ── Step 6: Configuration guidance ──────────────────────────────────────────

Write-Host ""
Write-Host "=============================================" -ForegroundColor Magenta
Write-Host "  MBOpenClacky installation complete!" -ForegroundColor Magenta
Write-Host "=============================================" -ForegroundColor Magenta
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Configure an API key (choose one method):"
Write-Host ""
Write-Host "     # PowerShell (environment variable, session-scoped)" -ForegroundColor Gray
Write-Host '     $env:CLACKY_API_KEY = "your-api-key"' -ForegroundColor White
Write-Host '     $env:CLACKY_BASE_URL = "https://api.anthropic.com"' -ForegroundColor White
Write-Host '     $env:CLACKY_MODEL = "claude-sonnet-4-6"' -ForegroundColor White
Write-Host ""
Write-Host "     # Or create a config file at:" -ForegroundColor Gray
Write-Host "     #   $env:USERPROFILE\.mbopenclacky\config.toml" -ForegroundColor White
Write-Host ""
Write-Host "  2. Run the agent:"
Write-Host ""
if ($buildTarget -eq "native" -and $found) {
    $exePath = @($found)[0].FullName
    Write-Host "     $exePath --message `"Hello`" --mode auto_approve" -ForegroundColor White
} else {
    Write-Host "     moon run cmd -- --message `"Hello`" --mode auto_approve" -ForegroundColor White
}
Write-Host ""
Write-Host "  3. For full documentation, see:" -ForegroundColor Gray
Write-Host "     docs/getting-started.md" -ForegroundColor White
Write-Host ""

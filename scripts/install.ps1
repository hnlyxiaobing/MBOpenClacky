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
.PARAMETER ChinaMirror
    Use China region mirror for downloads (when available).
.PARAMETER Target
    Override build target (native/wasm-gc).
#>

param(
    # Script now lives in scripts/; default ProjectRoot is the repo root (one level up)
    [string]$ProjectRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Definition)),
    [switch]$AutoInstall,
    [switch]$ChinaMirror,
    [string]$Target = ""
)

$ErrorActionPreference = "Stop"
$NativeHost = $null  # keep native host process alive for status checks

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

function Install-MoonBit {
    # NOTE: China mirror is not yet available; both paths use the official source.
    # Update this when a China CDN becomes available.
    $mirror = "https://cli.moonbitlang.com"
    if ($ChinaMirror) {
        Write-Warn "China mirror not yet available, using official source: $mirror"
    }
    Write-Step "Installing MoonBit toolchain..."
    try {
        $installScript = Invoke-WebRequest -Uri "$mirror/install/powershell.ps1" -UseBasicParsing
        Invoke-Expression $installScript.Content
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

# ── Version check ───────────────────────────────────────────────────────────

$versionMatch = [regex]::Match($moonVersion, '(\d+\.\d+\.\d+)')
if ($versionMatch.Success) {
    $moonVersionNum = $versionMatch.Groups[1].Value
    Write-OK "MoonBit version: $moonVersionNum"
} else {
    Write-Warn "Could not parse moon version: $moonVersion"
}

# ── Step 2: Check C compiler ────────────────────────────────────────────────

Write-Step "Checking C compiler (cl.exe)..."

$clCmd = Get-Command cl.exe -ErrorAction SilentlyContinue
$activated = $false
if (-not $clCmd) {
    Write-Warn "cl.exe not found in PATH. Attempting to activate MSVC environment..."

    # Try vswhere.exe to find VS installation dynamically
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vswhere) {
        $vsPath = & $vswhere -latest -property installationPath 2>$null
        if ($vsPath) {
            $vcvarsall = Join-Path $vsPath "VC\Auxiliary\Build\vcvarsall.bat"
            if (Test-Path $vcvarsall) {
                Write-Host "  Found VS at: $vsPath" -ForegroundColor Gray
                Write-Host "  Activating MSVC via vcvarsall.bat x64..." -ForegroundColor Gray
                cmd /c "`"$vcvarsall`" x64 >nul 2>&1 && set" | ForEach-Object {
                    if ($_ -match "^(.+?)=(.*)$") {
                        [Environment]::SetEnvironmentVariable($matches[1], $matches[2], "Process")
                    }
                }
                $clCmd = Get-Command cl.exe -ErrorAction SilentlyContinue
                if ($clCmd) {
                    $activated = $true
                    Write-OK "cl.exe activated: $($clCmd.Source)"
                }
            }
        }
    }

    # Fallback: check common VS paths if vswhere didn't work
    if (-not $activated) {
        $commonPaths = @(
            "$env:ProgramFiles\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat",
            "$env:ProgramFiles\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvarsall.bat",
            "$env:ProgramFiles\Microsoft Visual Studio\2022\Enterprise\VC\Auxiliary\Build\vcvarsall.bat",
            "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\Community\VC\Auxiliary\Build\vcvarsall.bat",
            "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\Professional\VC\Auxiliary\Build\vcvarsall.bat",
            "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\Enterprise\VC\Auxiliary\Build\vcvarsall.bat"
        )
        foreach ($vcvarsall in $commonPaths) {
            if (Test-Path $vcvarsall) {
                Write-Host "  Found vcvarsall at: $vcvarsall" -ForegroundColor Gray
                Write-Host "  Activating MSVC via vcvarsall.bat x64..." -ForegroundColor Gray
                cmd /c "`"$vcvarsall`" x64 >nul 2>&1 && set" | ForEach-Object {
                    if ($_ -match "^(.+?)=(.*)$") {
                        [Environment]::SetEnvironmentVariable($matches[1], $matches[2], "Process")
                    }
                }
                $clCmd = Get-Command cl.exe -ErrorAction SilentlyContinue
                if ($clCmd) {
                    $activated = $true
                    Write-OK "cl.exe activated: $($clCmd.Source)"
                    break
                }
            }
        }
    }

    if (-not $activated) {
        Write-Host "  Native builds require MSVC Build Tools." -ForegroundColor Yellow
        Write-Host "  Download from: https://visualstudio.microsoft.com/visual-cpp-build-tools/"
        Write-Host "  Or open 'x64 Native Tools Command Prompt' and re-run this script."
        Write-Host "  You can still build for wasm-gc without a C compiler."
        $hasCC = $false
    }
} else {
    Write-OK "cl.exe found: $($clCmd.Source)"
    $hasCC = $true
}

# Set $hasCC if activation succeeded
if ($activated) { $hasCC = $true }

# ── Step 3: Update & install dependencies ───────────────────────────────────

Write-Step "Updating MoonBit package index..."

Set-Location $ProjectRoot
moon update
if ($LASTEXITCODE -ne 0) {
    Write-Err "moon update failed (exit code: $LASTEXITCODE)"
    exit 1
}
Write-OK "Package index updated."

Write-Step "Installing project dependencies..."

moon install
if ($LASTEXITCODE -ne 0) {
    Write-Err "moon install failed (exit code: $LASTEXITCODE)"
    exit 1
}
Write-OK "Dependencies installed."

# ── Step 4: Build ────────────────────────────────────────────────────────────

# Determine build target: user override > auto-detect
if ($Target -ne "") {
    $buildTarget = $Target
    Write-OK "Using user-specified target: $buildTarget"
} else {
    $buildTarget = if ($hasCC) { "native" } else { "wasm-gc" }
}
Write-Step "Building project (target: $buildTarget)..."

moon build --target $buildTarget
if ($LASTEXITCODE -ne 0) {
    Write-Err "moon build failed (exit code: $LASTEXITCODE)"
    Write-Host "  Run 'moon check' for detailed error information."
    exit 1
}
Write-OK "Build succeeded."

# ── Step 5: Verify build artifacts ──────────────────────────────────────────

Write-Step "Verifying build artifacts..."

$buildDir = Join-Path $ProjectRoot "_build\$buildTarget\release\build\cmd"
$exePattern = "*.exe"
$found = Get-ChildItem -Path $buildDir -Filter $exePattern -ErrorAction SilentlyContinue

if (-not $found -and $buildTarget -eq "native") {
    # Also check alternative output locations
    $altDir = Join-Path $ProjectRoot "_build\$buildTarget\release\build"
    $found = Get-ChildItem -Path $altDir -Recurse -Filter $exePattern -ErrorAction SilentlyContinue
}

if ($found) {
    Write-OK "Build artifacts found:"
    $found | ForEach-Object { Write-Host "  $($_.FullName)" -ForegroundColor Gray }
} else {
    if ($buildTarget -eq "native") {
        Write-Warn "No .exe artifacts found in _build/$buildTarget/"
        Write-Host "  The build succeeded but no executable was produced."
        Write-Host "  Check that cmd/main.mbt contains a main() entry point."
    } else {
        Write-OK "wasm-gc build artifacts are in _build/$buildTarget/"
    }
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
    $exePath = $found[0].FullName
    Write-Host "     $exePath --message `"Hello`" --mode auto_approve" -ForegroundColor White
} else {
    Write-Host "     moon run cmd -- --message `"Hello`" --mode auto_approve" -ForegroundColor White
}
Write-Host ""
Write-Host "  3. For full documentation, see:" -ForegroundColor Gray
Write-Host "     docs/getting-started.md" -ForegroundColor White
Write-Host ""

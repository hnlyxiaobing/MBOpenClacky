#Requires -Version 5.1
<#
.SYNOPSIS
    Guard against shipping the insecure crypto stubs in a release build.
.DESCRIPTION
    Mirrors scripts/check-crypto-build.sh. Refuses a RELEASE build when
    MBOPENCLACKY_NO_OPENSSL is set to a non-empty value (unless
    MBOPENCLACKY_INSECURE_OK is also set), and warns for debug builds.
    The C layer in lib/brand/brand_stubs.c enforces the same rule at compile
    time via MBOPENCLACKY_INSECURE_DEBUG_BUILD.
.PARAMETER BuildKind
    "release" (default) or "debug".
#>
param(
    [string]$BuildKind = "release"
)

$ErrorActionPreference = "Stop"

$insecure = -not [string]::IsNullOrEmpty($env:MBOPENCLACKY_NO_OPENSSL)
if ($insecure) {
    if ($BuildKind -eq "release" -and [string]::IsNullOrEmpty($env:MBOPENCLACKY_INSECURE_OK)) {
        Write-Error (
            "Refusing to build RELEASE with MBOPENCLACKY_NO_OPENSSL. " +
            "This would ship the insecure crypto stubs (non-random nonces, " +
            "all-zero ciphertext) from lib/brand/brand_stubs.c. " +
            "Drop -DMBOPENCLACKY_NO_OPENSSL, or for a debug-only minimal build " +
            "set MBOPENCLACKY_INSECURE_OK=1 and MBOPENCLACKY_INSECURE_DEBUG_BUILD=1."
        )
        exit 1
    }
    Write-Warning "Building with MBOPENCLACKY_NO_OPENSSL (insecure crypto stubs). Not for production use."
}

Write-Host "OK: crypto build guard passed (kind=$BuildKind)."

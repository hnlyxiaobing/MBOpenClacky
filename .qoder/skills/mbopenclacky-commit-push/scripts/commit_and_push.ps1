[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$MessageFile,

    [string]$Remote = "origin",

    [string]$Branch,

    [switch]$DryRun,

    [switch]$NoPush
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Invoke-Git {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Args
    )

    $output = & git @Args 2>&1
    if ($LASTEXITCODE -ne 0) {
        $rendered = $Args -join " "
        throw "git $rendered failed.`n$output"
    }
    return $output
}

if (-not (Test-Path -LiteralPath $MessageFile)) {
    throw "Commit message file not found: $MessageFile"
}

$repoRoot = (Invoke-Git -Args @("rev-parse", "--show-toplevel") | Out-String).Trim()
if (-not $repoRoot) {
    throw "Unable to determine git repository root."
}

Push-Location $repoRoot
try {
    $preStatus = (Invoke-Git -Args @("status", "--short", "--untracked-files=all") | Out-String).Trim()
    if (-not $preStatus) {
        throw "Working tree is clean. Nothing to commit."
    }

    $targetBranch = $Branch
    if (-not $targetBranch) {
        $targetBranch = (Invoke-Git -Args @("rev-parse", "--abbrev-ref", "HEAD") | Out-String).Trim()
    }
    if (-not $targetBranch -or $targetBranch -eq "HEAD") {
        throw "Detached HEAD is not supported by this helper. Specify -Branch explicitly."
    }

    $message = Get-Content -LiteralPath $MessageFile -Raw

    if ($DryRun) {
        $previewFiles = (Invoke-Git -Args @("status", "--short", "--untracked-files=all") | Out-String).Trim()

        Write-Host "Repository: $repoRoot"
        Write-Host "Branch: $targetBranch"
        Write-Host "Remote: $Remote"
        Write-Host "Files:"
        Write-Host $previewFiles
        Write-Host ""
        Write-Host "Commit message:"
        Write-Host $message
        return
    }

    Invoke-Git -Args @("add", "-A") | Out-Null

    $stagedFiles = (Invoke-Git -Args @("diff", "--cached", "--name-status", "--find-renames") | Out-String).Trim()
    if (-not $stagedFiles) {
        throw "No staged changes were found after git add -A."
    }

    $commitOutput = Invoke-Git -Args @("commit", "-F", $MessageFile)
    $commitSha = (Invoke-Git -Args @("rev-parse", "--short", "HEAD") | Out-String).Trim()

    if ($NoPush) {
        Write-Host $commitOutput
        Write-Host "Committed $commitSha on $targetBranch without pushing."
        return
    }

    $pushOutput = Invoke-Git -Args @("push", $Remote, $targetBranch)
    Write-Host $commitOutput
    Write-Host $pushOutput
    Write-Host "Committed and pushed $commitSha to $Remote/$targetBranch."
}
finally {
    Pop-Location
}
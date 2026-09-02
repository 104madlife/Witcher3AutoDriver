[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ReceiptPath,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-Sha256 {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Assert-ChildPath {
    param([string]$Path, [string]$Parent, [string]$Label)
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $fullParent = [System.IO.Path]::GetFullPath($Parent).TrimEnd('\')
    if (-not $fullPath.StartsWith($fullParent + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label escapes its allowed root: $fullPath"
    }
    return $fullPath
}

function Remove-EmptyRuntimeTree {
    param([string]$PayloadPath, [string]$RuntimeRoot, [bool]$RemoveRoot)
    if (Test-Path -LiteralPath $PayloadPath -PathType Leaf) {
        Remove-Item -LiteralPath $PayloadPath -Force
    }
    $current = Split-Path -Parent $PayloadPath
    while ($current.StartsWith($RuntimeRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        if (-not (Test-Path -LiteralPath $current -PathType Container)) {
            break
        }
        if ((Get-ChildItem -LiteralPath $current -Force | Measure-Object).Count -gt 0) {
            break
        }
        if ($current -eq $RuntimeRoot -and -not $RemoveRoot) {
            break
        }
        [System.IO.Directory]::Delete($current, $false)
        if ($current -eq $RuntimeRoot) {
            break
        }
        $current = Split-Path -Parent $current
    }
}

$resolvedReceiptPath = (Resolve-Path -LiteralPath $ReceiptPath).Path
$receipt = Get-Content -Raw -LiteralPath $resolvedReceiptPath | ConvertFrom-Json
if ($receipt.kind -ne "witcher3-autodriver-deployment" -or $receipt.result -ne "passed" -or $receipt.payloads.Count -ne 1) {
    throw "Unsupported or unsuccessful deployment receipt: $resolvedReceiptPath"
}

$gameRoot = (Resolve-Path -LiteralPath $receipt.gameRoot).Path.TrimEnd('\')
$modsRoot = Join-Path $gameRoot "mods"
$expectedRuntimePath = Join-Path $modsRoot "modAutoDriver"
$runtimePath = [System.IO.Path]::GetFullPath([string]$receipt.runtimePath)
if ($runtimePath -ne [System.IO.Path]::GetFullPath($expectedRuntimePath)) {
    throw "Receipt runtime path is not the exact AutoDriver runtime path: $runtimePath"
}

$payload = $receipt.payloads[0]
$destination = Assert-ChildPath -Path $payload.destination -Parent $runtimePath -Label "Receipt payload"
if (-not (Test-Path -LiteralPath $destination -PathType Leaf)) {
    throw "Deployed payload is missing: $destination"
}
$currentHash = Get-Sha256 $destination
if ($currentHash -ne $payload.deployedSha256) {
    throw "Refusing rollback because the deployed payload changed: expected=$($payload.deployedSha256) actual=$currentHash"
}

if (-not $DryRun) {
    $running = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '^(witcher3|REDlauncher)$' })
    if ($running.Count -gt 0) {
        throw "Refusing rollback while the game or REDlauncher is running: $($running.ProcessName -join ', ')"
    }
}

$previousKind = [string]$receipt.previousRuntime.kind
if ($previousKind -notin @("junction", "directory", "absent")) {
    throw "Unsupported previous runtime kind: $previousKind"
}
if ($previousKind -eq "junction") {
    if (-not $receipt.previousRuntime.target -or -not (Test-Path -LiteralPath $receipt.previousRuntime.target -PathType Container)) {
        throw "Cannot restore missing prior junction target: $($receipt.previousRuntime.target)"
    }
}
if ($previousKind -eq "directory" -and $payload.previousExists) {
    if (-not $payload.backup -or -not (Test-Path -LiteralPath $payload.backup -PathType Leaf)) {
        throw "Missing rollback backup: $($payload.backup)"
    }
    $backupHash = Get-Sha256 $payload.backup
    if ($backupHash -ne $payload.previousSha256) {
        throw "Rollback backup hash mismatch: expected=$($payload.previousSha256) actual=$backupHash"
    }
}

Write-Output "Rollback mode: $previousKind"
Write-Output "Verified deployed payload: $destination"
if ($previousKind -eq "junction") {
    Write-Output "Junction to restore: $runtimePath -> $($receipt.previousRuntime.target)"
}

if ($DryRun) {
    Write-Output "Rollback Dry Run complete. No filesystem changes were made."
    exit 0
}

if ($previousKind -eq "directory" -and $payload.previousExists) {
    Copy-Item -LiteralPath $payload.backup -Destination $destination -Force
    $restoredHash = Get-Sha256 $destination
    if ($restoredHash -ne $payload.previousSha256) {
        throw "Restored payload hash mismatch: expected=$($payload.previousSha256) actual=$restoredHash"
    }
}
else {
    Remove-EmptyRuntimeTree -PayloadPath $destination -RuntimeRoot $runtimePath -RemoveRoot ($previousKind -ne "directory")
}

if ($previousKind -eq "junction") {
    if (Test-Path -LiteralPath $runtimePath) {
        throw "Runtime directory was not empty after removing the receipt-owned payload; refusing to replace it with a junction."
    }
    New-Item -ItemType Junction -Path $runtimePath -Target $receipt.previousRuntime.target | Out-Null
    $restoredItem = Get-Item -LiteralPath $runtimePath -Force
    if ([string]$restoredItem.LinkType -ne "Junction") {
        throw "Failed to recreate the prior junction."
    }
    $expectedTarget = (Resolve-Path -LiteralPath $receipt.previousRuntime.target).Path.TrimEnd('\')
    $actualTarget = (Resolve-Path -LiteralPath ([string]$restoredItem.Target)).Path.TrimEnd('\')
    if ($expectedTarget -ne $actualTarget) {
        throw "Restored junction target mismatch: expected=$expectedTarget actual=$actualTarget"
    }
}

$rollbackReceipt = [ordered]@{
    schemaVersion = 1
    kind = "witcher3-autodriver-rollback"
    rolledBackAt = (Get-Date).ToString("o")
    deploymentReceipt = $resolvedReceiptPath
    gameRoot = $gameRoot
    restoredRuntimeKind = $previousKind
    restoredJunctionTarget = if ($previousKind -eq "junction") { [string]$receipt.previousRuntime.target } else { $null }
    payload = [ordered]@{
        destination = $destination
        restoredPrevious = [bool]$payload.previousExists
        expectedSha256 = if ($payload.previousExists) { [string]$payload.previousSha256 } else { $null }
    }
    result = "passed"
}

$rollbackPath = Join-Path (Split-Path -Parent $resolvedReceiptPath) "rollback-$($receipt.deploymentId).json"
$rollbackReceipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $rollbackPath -Encoding UTF8
Write-Output "Rollback passed. Receipt: $rollbackPath"

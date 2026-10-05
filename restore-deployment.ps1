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

function Remove-EmptyParents {
    param([string]$StartPath, [string]$StopRoot, [bool]$RemoveStopRoot)
    $current = $StartPath
    while ($current.StartsWith($StopRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        if (-not (Test-Path -LiteralPath $current -PathType Container)) { break }
        if ((Get-ChildItem -LiteralPath $current -Force | Measure-Object).Count -gt 0) { break }
        if ($current -eq $StopRoot -and -not $RemoveStopRoot) { break }
        [System.IO.Directory]::Delete($current, $false)
        if ($current -eq $StopRoot) { break }
        $current = Split-Path -Parent $current
    }
}

$resolvedReceiptPath = (Resolve-Path -LiteralPath $ReceiptPath).Path
$receiptDirectory = Split-Path -Parent $resolvedReceiptPath
$receipt = Get-Content -Raw -LiteralPath $resolvedReceiptPath | ConvertFrom-Json
if ($receipt.schemaVersion -ne 2 -or $receipt.kind -ne "witcher3-autodriver-deployment" -or $receipt.result -ne "passed" -or $receipt.payloads.Count -ne 1) {
    throw "Unsupported or unsuccessful deployment receipt: $resolvedReceiptPath"
}

$gameRoot = (Resolve-Path -LiteralPath $receipt.gameRoot).Path.TrimEnd('\')
$runtimePath = [System.IO.Path]::GetFullPath([string]$receipt.runtimePath)
$expectedRuntimePath = Join-Path $gameRoot "mods\modAutoDriver"
if ($runtimePath -ne [System.IO.Path]::GetFullPath($expectedRuntimePath)) {
    throw "Receipt runtime path is not the exact AutoDriver runtime path: $runtimePath"
}

$payload = $receipt.payloads[0]
$destination = Assert-ChildPath -Path $payload.destination -Parent $runtimePath -Label "Receipt AutoDriver payload"
if (-not (Test-Path -LiteralPath $destination -PathType Leaf)) {
    throw "Deployed AutoDriver payload is missing: $destination"
}
if ((Get-Sha256 $destination) -ne $payload.deployedSha256) {
    throw "Refusing rollback because the deployed AutoDriver payload changed."
}

$previousKind = [string]$receipt.previousRuntime.kind
if ($previousKind -notin @("junction", "directory", "absent")) {
    throw "Unsupported previous runtime kind: $previousKind"
}
if ($payload.previousExists) {
    $autoBackup = Assert-ChildPath -Path $payload.backup -Parent $receiptDirectory -Label "AutoDriver backup"
    if (-not (Test-Path -LiteralPath $autoBackup -PathType Leaf) -or (Get-Sha256 $autoBackup) -ne $payload.previousSha256) {
        throw "AutoDriver rollback backup is missing or changed: $autoBackup"
    }
}

$registry = $receipt.bootstrapRegistry
$expectedRegistryPath = Join-Path $gameRoot "mods\modBootstrap-registry\content\scripts\local\mods_registry.ws"
$registryPath = [System.IO.Path]::GetFullPath([string]$registry.path)
if ($registryPath -ne [System.IO.Path]::GetFullPath($expectedRegistryPath)) {
    throw "Receipt registry path is not the expected Bootstrap registry path: $registryPath"
}
if ($registry.mode -in @("create", "update")) {
    if (-not (Test-Path -LiteralPath $registryPath -PathType Leaf) -or (Get-Sha256 $registryPath) -ne $registry.deployedSha256) {
        throw "Refusing rollback because the Bootstrap registry changed after deployment."
    }
}
if ($registry.mode -eq "update") {
    $registryBackup = Assert-ChildPath -Path $registry.backup -Parent $receiptDirectory -Label "Bootstrap registry backup"
    if (-not (Test-Path -LiteralPath $registryBackup -PathType Leaf) -or (Get-Sha256 $registryBackup) -ne $registry.previousSha256) {
        throw "Bootstrap registry rollback backup is missing or changed: $registryBackup"
    }
}

$userInput = $receipt.userInput
$userInputPath = [System.IO.Path]::GetFullPath([string]$userInput.path)
if ($userInput.mode -in @("create", "update")) {
    if (-not (Test-Path -LiteralPath $userInputPath -PathType Leaf) -or (Get-Sha256 $userInputPath) -ne $userInput.deployedSha256) {
        throw "Refusing rollback because the user input file changed after deployment."
    }
}
if ($userInput.mode -eq "update") {
    $inputBackup = Assert-ChildPath -Path $userInput.backup -Parent $receiptDirectory -Label "User input backup"
    if (-not (Test-Path -LiteralPath $inputBackup -PathType Leaf) -or (Get-Sha256 $inputBackup) -ne $userInput.previousSha256) {
        throw "User input rollback backup is missing or changed: $inputBackup"
    }
}

$dependencyRecords = @($receipt.dependencies)
foreach ($dependency in $dependencyRecords) {
    $expectedRoot = switch ([string]$dependency.component) {
        "BootstrapMod" { Join-Path $gameRoot "mods\modBootstrap" }
        "BootstrapDlc" { Join-Path $gameRoot "dlc\dlcBootstrap" }
        default { throw "Unsupported dependency component in receipt: $($dependency.component)" }
    }
    $dependencyRoot = [System.IO.Path]::GetFullPath([string]$dependency.root)
    if ($dependencyRoot -ne [System.IO.Path]::GetFullPath($expectedRoot)) {
        throw "Receipt dependency root is not the expected path: $dependencyRoot"
    }
    if ($dependency.mode -eq "install") {
        foreach ($file in $dependency.files) {
            $dependencyFile = Assert-ChildPath -Path $file.destination -Parent $dependencyRoot -Label "Dependency payload"
            if (-not (Test-Path -LiteralPath $dependencyFile -PathType Leaf) -or (Get-Sha256 $dependencyFile) -ne $file.sha256) {
                throw "Refusing rollback because an installed dependency file changed: $dependencyFile"
            }
        }
    }
    elseif ($dependency.mode -ne "reuse") {
        throw "Unsupported dependency deployment mode: $($dependency.mode)"
    }
}

if (-not $DryRun) {
    $running = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '^(witcher3|REDlauncher)$' })
    if ($running.Count -gt 0) {
        throw "Refusing rollback while the game or REDlauncher is running: $($running.ProcessName -join ', ')"
    }
}

Write-Output "Rollback AutoDriver runtime to: $previousKind"
Write-Output "BootstrapRegistry: $($registry.mode)"
Write-Output "UserInput: $($userInput.mode)"
foreach ($dependency in $dependencyRecords) {
    Write-Output "$($dependency.component): $($dependency.mode)"
}
if ($DryRun) {
    Write-Output "Rollback Dry Run complete. No filesystem changes were made."
    exit 0
}

if ($previousKind -eq "directory" -and $payload.previousExists) {
    Copy-Item -LiteralPath $autoBackup -Destination $destination -Force
    if ((Get-Sha256 $destination) -ne $payload.previousSha256) {
        throw "Restored AutoDriver payload hash mismatch."
    }
}
else {
    Remove-Item -LiteralPath $destination -Force
    Remove-EmptyParents -StartPath (Split-Path -Parent $destination) -StopRoot $runtimePath -RemoveStopRoot ($previousKind -ne "directory")
}

if ($previousKind -eq "junction") {
    if (Test-Path -LiteralPath $runtimePath) {
        throw "Cannot recreate prior junction because the runtime path is not empty: $runtimePath"
    }
    if (-not (Test-Path -LiteralPath $receipt.previousRuntime.target -PathType Container)) {
        throw "Prior junction target no longer exists: $($receipt.previousRuntime.target)"
    }
    New-Item -ItemType Junction -Path $runtimePath -Target $receipt.previousRuntime.target | Out-Null
    $restoredItem = Get-Item -LiteralPath $runtimePath -Force
    if ([string]$restoredItem.LinkType -ne "Junction") {
        throw "Failed to recreate the prior AutoDriver junction."
    }
}

if ($userInput.mode -eq "update") {
    Copy-Item -LiteralPath $inputBackup -Destination $userInputPath -Force
}
elseif ($userInput.mode -eq "create") {
    Remove-Item -LiteralPath $userInputPath -Force
}

if ($registry.mode -eq "update") {
    Copy-Item -LiteralPath $registryBackup -Destination $registryPath -Force
}
elseif ($registry.mode -eq "create") {
    Remove-Item -LiteralPath $registryPath -Force
    Remove-EmptyParents -StartPath (Split-Path -Parent $registryPath) -StopRoot (Join-Path $gameRoot "mods\modBootstrap-registry") -RemoveStopRoot $true
}

foreach ($dependency in @($dependencyRecords | Sort-Object { $_.root.Length } -Descending)) {
    if ($dependency.mode -ne "install") { continue }
    $dependencyRoot = [System.IO.Path]::GetFullPath([string]$dependency.root)
    foreach ($file in @($dependency.files | Sort-Object { $_.destination.Length } -Descending)) {
        Remove-Item -LiteralPath $file.destination -Force
        Remove-EmptyParents -StartPath (Split-Path -Parent $file.destination) -StopRoot $dependencyRoot -RemoveStopRoot $true
    }
}

$rollbackReceipt = [ordered]@{
    schemaVersion = 2
    kind = "witcher3-autodriver-rollback"
    rolledBackAt = (Get-Date).ToString("o")
    deploymentReceipt = $resolvedReceiptPath
    gameRoot = $gameRoot
    restoredRuntimeKind = $previousKind
    restoredJunctionTarget = if ($previousKind -eq "junction") { [string]$receipt.previousRuntime.target } else { $null }
    bootstrapRegistryMode = [string]$registry.mode
    userInputMode = [string]$userInput.mode
    removedDependencies = @($dependencyRecords | Where-Object { $_.mode -eq "install" } | ForEach-Object { $_.component })
    result = "passed"
}

$rollbackPath = Join-Path $receiptDirectory "rollback-$($receipt.deploymentId).json"
$rollbackReceipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $rollbackPath -Encoding UTF8
Write-Output "Rollback passed. Receipt: $rollbackPath"

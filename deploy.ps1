[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$GameRoot,
    [Parameter(Mandatory = $true)]
    [string]$UserInputPath,
    [ValidateSet("Release", "Debug")]
    [string]$Configuration = "Release",
    [string]$PackageManifestPath,
    [string]$ExpectedJunctionTarget,
    [string]$ReceiptDirectory,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$projectRoot = $PSScriptRoot
$resolvedGameRoot = (Resolve-Path -LiteralPath $GameRoot).Path.TrimEnd('\')
$modsRoot = Join-Path $resolvedGameRoot "mods"
$runtimePath = Join-Path $modsRoot "modAutoDriver"
$baselineIntegrationPath = Join-Path $projectRoot "baselines\legacy-current\integration-state.json"

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

function Get-RuntimeState {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return [ordered]@{ kind = "absent"; target = $null }
    }
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.LinkType) {
        if ([string]$item.LinkType -ne "Junction") {
            throw "Unsupported reparse-point type at runtime destination: $($item.LinkType)"
        }
        return [ordered]@{ kind = "junction"; target = [string]$item.Target }
    }
    if (-not $item.PSIsContainer) {
        throw "Runtime destination exists but is not a directory: $Path"
    }
    return [ordered]@{ kind = "directory"; target = $null }
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

foreach ($required in @(
    (Join-Path $resolvedGameRoot "bin\x64\witcher3.exe"),
    (Join-Path $resolvedGameRoot "bin\x64_dx12\witcher3.exe"),
    $modsRoot
)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Invalid game root; missing required path: $required"
    }
}

if (-not $DryRun) {
    $running = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '^(witcher3|REDlauncher)$' })
    if ($running.Count -gt 0) {
        throw "Refusing deployment while the game or REDlauncher is running: $($running.ProcessName -join ', ')"
    }
}

& (Join-Path $projectRoot "validate-project.ps1") -GameRoot $resolvedGameRoot -UserInputPath $UserInputPath -NoReceipt

if (-not $PackageManifestPath) {
    $PackageManifestPath = Join-Path $projectRoot "artifacts\$Configuration\package-manifest.json"
}
if (-not (Test-Path -LiteralPath $PackageManifestPath -PathType Leaf)) {
    throw "Missing package manifest: $PackageManifestPath"
}

$resolvedManifestPath = (Resolve-Path -LiteralPath $PackageManifestPath).Path
$manifest = Get-Content -Raw -LiteralPath $resolvedManifestPath | ConvertFrom-Json
if ($manifest.kind -ne "witcher3-autodriver-runtime-package" -or $manifest.payloads.Count -ne 1) {
    throw "Unsupported package manifest: $resolvedManifestPath"
}
if ($manifest.sourceDirty) {
    throw "Refusing to deploy a package produced from a dirty source tree."
}

$manifestDirectory = Split-Path -Parent $resolvedManifestPath
$payload = $manifest.payloads[0]
$packagePayloadPath = Assert-ChildPath -Path (Join-Path $manifestDirectory $payload.packagePath) -Parent $manifestDirectory -Label "Package payload"
if (-not (Test-Path -LiteralPath $packagePayloadPath -PathType Leaf)) {
    throw "Missing package payload: $packagePayloadPath"
}
$packageHash = Get-Sha256 $packagePayloadPath
if ($packageHash -ne $payload.sha256) {
    throw "Package payload hash mismatch: expected=$($payload.sha256) actual=$packageHash"
}

$destinationPayloadPath = Assert-ChildPath -Path (Join-Path $runtimePath $payload.runtimeRelativePath) -Parent $runtimePath -Label "Runtime payload"
$runtimeState = Get-RuntimeState -Path $runtimePath

if ($runtimeState.kind -eq "junction") {
    if (-not $ExpectedJunctionTarget) {
        if (Test-Path -LiteralPath $baselineIntegrationPath -PathType Leaf) {
            $baselineIntegration = Get-Content -Raw -LiteralPath $baselineIntegrationPath | ConvertFrom-Json
            if ($baselineIntegration.gameRoot -eq $resolvedGameRoot) {
                $ExpectedJunctionTarget = $baselineIntegration.runtimeDestination.target
            }
        }
    }
    if (-not $ExpectedJunctionTarget) {
        throw "A junction exists at the runtime destination. Supply -ExpectedJunctionTarget for this game root."
    }
    $resolvedExpected = (Resolve-Path -LiteralPath $ExpectedJunctionTarget).Path.TrimEnd('\')
    $resolvedActual = (Resolve-Path -LiteralPath $runtimeState.target).Path.TrimEnd('\')
    if ($resolvedExpected -ne $resolvedActual) {
        throw "Unexpected junction target: expected=$resolvedExpected actual=$resolvedActual"
    }
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
if (-not $ReceiptDirectory) {
    $ReceiptDirectory = Join-Path $projectRoot "build\deployments"
}
$resolvedReceiptDirectory = [System.IO.Path]::GetFullPath($ReceiptDirectory)
$backupDirectory = Join-Path $resolvedReceiptDirectory "backups\$timestamp"
$receiptPath = Join-Path $resolvedReceiptDirectory "deployment-$timestamp.json"

$registryPath = Join-Path $resolvedGameRoot "mods\modBootstrap-registry\content\scripts\local\mods_registry.ws"
$externalBefore = [ordered]@{
    bootstrapRegistry = [ordered]@{ path = $registryPath; sha256 = Get-Sha256 $registryPath }
    userInput = [ordered]@{ path = (Resolve-Path -LiteralPath $UserInputPath).Path; sha256 = Get-Sha256 $UserInputPath }
}

$previousExists = Test-Path -LiteralPath $destinationPayloadPath -PathType Leaf
$previousHash = if ($previousExists) { Get-Sha256 $destinationPayloadPath } else { $null }
$backupPath = if ($runtimeState.kind -eq "directory" -and $previousExists) { Join-Path $backupDirectory $payload.runtimeRelativePath } else { $null }

Write-Output "Deployment mode: $($runtimeState.kind)"
if ($runtimeState.kind -eq "junction") {
    Write-Output "Verified junction target: $($runtimeState.target)"
}
Write-Output "Payload: $packagePayloadPath"
Write-Output "Destination: $destinationPayloadPath"
Write-Output "Payload SHA-256: $packageHash"
Write-Output "Receipt: $receiptPath"

if ($DryRun) {
    Write-Output "Dry Run complete. No filesystem changes were made."
    exit 0
}

$junctionRemoved = $false
$runtimeCreated = $false
$payloadWritten = $false

try {
    if ($runtimeState.kind -eq "junction") {
        [System.IO.Directory]::Delete($runtimePath, $false)
        $junctionRemoved = $true
        if (Test-Path -LiteralPath $runtimePath) {
            throw "Failed to remove the verified junction entry."
        }
        if (-not (Test-Path -LiteralPath $runtimeState.target -PathType Container)) {
            throw "Junction target disappeared during deployment: $($runtimeState.target)"
        }
        New-Item -ItemType Directory -Path $runtimePath | Out-Null
        $runtimeCreated = $true
    }
    elseif ($runtimeState.kind -eq "absent") {
        New-Item -ItemType Directory -Path $runtimePath | Out-Null
        $runtimeCreated = $true
    }

    if ($backupPath) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $backupPath) -Force | Out-Null
        Copy-Item -LiteralPath $destinationPayloadPath -Destination $backupPath
        if ((Get-Sha256 $backupPath) -ne $previousHash) {
            throw "Backup hash verification failed: $backupPath"
        }
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $destinationPayloadPath) -Force | Out-Null
    Copy-Item -LiteralPath $packagePayloadPath -Destination $destinationPayloadPath -Force
    $payloadWritten = $true
    $deployedHash = Get-Sha256 $destinationPayloadPath
    if ($deployedHash -ne $packageHash) {
        throw "Deployed payload hash mismatch: expected=$packageHash actual=$deployedHash"
    }

    $externalAfter = [ordered]@{
        bootstrapRegistry = [ordered]@{ path = $registryPath; sha256 = Get-Sha256 $registryPath }
        userInput = [ordered]@{ path = (Resolve-Path -LiteralPath $UserInputPath).Path; sha256 = Get-Sha256 $UserInputPath }
    }
    if ($externalBefore.bootstrapRegistry.sha256 -ne $externalAfter.bootstrapRegistry.sha256 -or $externalBefore.userInput.sha256 -ne $externalAfter.userInput.sha256) {
        throw "An external verify-only integration file changed during deployment."
    }

    $receipt = [ordered]@{
        schemaVersion = 1
        kind = "witcher3-autodriver-deployment"
        deploymentId = $timestamp
        deployedAt = (Get-Date).ToString("o")
        sourceCommit = $manifest.sourceCommit
        gameRoot = $resolvedGameRoot
        runtimePath = $runtimePath
        previousRuntime = $runtimeState
        packageManifest = [ordered]@{ path = $resolvedManifestPath; sha256 = Get-Sha256 $resolvedManifestPath }
        payloads = @(
            [ordered]@{
                name = $payload.name
                destination = $destinationPayloadPath
                deployedSha256 = $deployedHash
                previousExists = $previousExists
                previousSha256 = $previousHash
                backup = $backupPath
            }
        )
        externalBefore = $externalBefore
        externalAfter = $externalAfter
        result = "passed"
    }

    New-Item -ItemType Directory -Path $resolvedReceiptDirectory -Force | Out-Null
    $receipt | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $receiptPath -Encoding UTF8
    $verifiedReceipt = Get-Content -Raw -LiteralPath $receiptPath | ConvertFrom-Json
    if ($verifiedReceipt.result -ne "passed" -or $verifiedReceipt.payloads[0].deployedSha256 -ne $deployedHash) {
        throw "Deployment receipt verification failed."
    }

    Write-Output "Deployment passed. Receipt: $receiptPath"
}
catch {
    $failure = $_
    try {
        if ($payloadWritten -and (Test-Path -LiteralPath $destinationPayloadPath -PathType Leaf)) {
            if ($runtimeState.kind -eq "directory" -and $previousExists -and $backupPath -and (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
                Copy-Item -LiteralPath $backupPath -Destination $destinationPayloadPath -Force
            }
            else {
                Remove-EmptyRuntimeTree -PayloadPath $destinationPayloadPath -RuntimeRoot $runtimePath -RemoveRoot ($runtimeState.kind -ne "directory")
            }
        }
        elseif ($runtimeCreated -and (Test-Path -LiteralPath $runtimePath -PathType Container) -and (Get-ChildItem -LiteralPath $runtimePath -Force | Measure-Object).Count -eq 0) {
            [System.IO.Directory]::Delete($runtimePath, $false)
        }

        if ($junctionRemoved -and -not (Test-Path -LiteralPath $runtimePath)) {
            New-Item -ItemType Junction -Path $runtimePath -Target $runtimeState.target | Out-Null
        }
    }
    catch {
        Write-Warning "Automatic rollback also failed: $($_.Exception.Message)"
    }
    throw $failure
}

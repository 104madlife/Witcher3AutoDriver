[CmdletBinding()]
param(
    [string]$RealGameRoot = "E:\SteamLibrary\steamapps\common\The Witcher 3",
    [string]$RealUserInputPath = "C:\Users\64617\Documents\The Witcher 3\input.settings"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$testRoot = [System.IO.Path]::GetFullPath((Join-Path $projectRoot "build\test-deployment"))
$allowedRoot = [System.IO.Path]::GetFullPath((Join-Path $projectRoot "build"))
if (-not $testRoot.StartsWith($allowedRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Unsafe test root: $testRoot"
}
if (Test-Path -LiteralPath $testRoot) {
    Remove-Item -LiteralPath $testRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $testRoot | Out-Null

function Get-Sha256 {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function New-GameFixture {
    param([string]$Name)
    $root = Join-Path $testRoot $Name
    $game = Join-Path $root "game"
    $input = Join-Path $root "user-input.settings"
    New-Item -ItemType Directory -Path @(
        (Join-Path $game "bin\x64"),
        (Join-Path $game "bin\x64_dx12"),
        (Join-Path $game "mods\modBootstrap"),
        (Join-Path $game "mods\modBootstrap-registry\content\scripts\local"),
        (Join-Path $game "mods\modStoryboardUi"),
        (Join-Path $game "dlc\dlcStoryboardUi\content")
    ) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $RealGameRoot "bin\x64\witcher3.exe") -Destination (Join-Path $game "bin\x64\witcher3.exe")
    Copy-Item -LiteralPath (Join-Path $RealGameRoot "bin\x64_dx12\witcher3.exe") -Destination (Join-Path $game "bin\x64_dx12\witcher3.exe")
    Copy-Item -LiteralPath (Join-Path $RealGameRoot "mods\modBootstrap-registry\content\scripts\local\mods_registry.ws") -Destination (Join-Path $game "mods\modBootstrap-registry\content\scripts\local\mods_registry.ws")
    Copy-Item -LiteralPath (Join-Path $RealGameRoot "dlc\dlcStoryboardUi\content\blob0.bundle") -Destination (Join-Path $game "dlc\dlcStoryboardUi\content\blob0.bundle")
    Copy-Item -LiteralPath $RealUserInputPath -Destination $input
    return [ordered]@{
        root = $root
        game = $game
        input = $input
        receipts = (Join-Path $root "receipts")
    }
}

function Get-FixtureFingerprint {
    param([string]$Root)
    $records = [System.Collections.Generic.List[string]]::new()
    foreach ($item in Get-ChildItem -LiteralPath $Root -Recurse -Force | Sort-Object FullName) {
        $relative = $item.FullName.Substring($Root.Length)
        if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            $records.Add("LINK|$relative|$($item.LinkType)|$($item.Target)")
        }
        elseif (-not $item.PSIsContainer) {
            $records.Add("FILE|$relative|$($item.Length)|$(Get-Sha256 $item.FullName)")
        }
    }
    return $records -join "`n"
}

function Get-LatestDeploymentReceipt {
    param([string]$Directory)
    return (Get-ChildItem -LiteralPath $Directory -Filter "deployment-*.json" -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
}

function Assert-Throws {
    param([scriptblock]$Operation, [string]$Label)
    $threw = $false
    try {
        & $Operation
    }
    catch {
        $threw = $true
        Write-Output "EXPECTED FAILURE [$Label]: $($_.Exception.Message.Split("`n")[0])"
    }
    if (-not $threw) {
        throw "Expected failure did not occur: $Label"
    }
}

$deploy = Join-Path $projectRoot "deploy.ps1"
$restore = Join-Path $projectRoot "restore-deployment.ps1"
$manifest = Join-Path $projectRoot "artifacts\Release\package-manifest.json"
$expectedPayloadHash = (Get-Content -Raw -LiteralPath $manifest | ConvertFrom-Json).payloads[0].sha256

Write-Output "CASE: junction"
$case = New-GameFixture -Name "junction"
$legacy = Join-Path $case.root "legacy-mod"
New-Item -ItemType Directory -Path (Join-Path $legacy "content\scripts\local") -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $projectRoot "content\scripts\local\mod_autodriver.ws") -Destination (Join-Path $legacy "content\scripts\local\mod_autodriver.ws")
New-Item -ItemType Junction -Path (Join-Path $case.game "mods\modAutoDriver") -Target $legacy | Out-Null
$legacyHash = Get-Sha256 (Join-Path $legacy "content\scripts\local\mod_autodriver.ws")
$before = Get-FixtureFingerprint $case.root
& $deploy -GameRoot $case.game -UserInputPath $case.input -PackageManifestPath $manifest -ExpectedJunctionTarget $legacy -ReceiptDirectory $case.receipts -DryRun
if ($before -ne (Get-FixtureFingerprint $case.root)) { throw "Junction deployment Dry Run changed fixture state" }
& $deploy -GameRoot $case.game -UserInputPath $case.input -PackageManifestPath $manifest -ExpectedJunctionTarget $legacy -ReceiptDirectory $case.receipts
$runtimeItem = Get-Item -LiteralPath (Join-Path $case.game "mods\modAutoDriver") -Force
if ($runtimeItem.LinkType) { throw "Junction deployment did not produce a real directory" }
$deployedPath = Join-Path $case.game "mods\modAutoDriver\content\scripts\local\mod_autodriver.ws"
if ((Get-Sha256 $deployedPath) -ne $expectedPayloadHash) { throw "Junction deployment payload hash mismatch" }
if ((Get-Sha256 (Join-Path $legacy "content\scripts\local\mod_autodriver.ws")) -ne $legacyHash) { throw "Legacy junction target changed" }
$receipt = Get-LatestDeploymentReceipt $case.receipts
$beforeRollback = Get-FixtureFingerprint $case.root
& $restore -ReceiptPath $receipt -DryRun
if ($beforeRollback -ne (Get-FixtureFingerprint $case.root)) { throw "Junction rollback Dry Run changed fixture state" }
& $restore -ReceiptPath $receipt
$restored = Get-Item -LiteralPath (Join-Path $case.game "mods\modAutoDriver") -Force
if ([string]$restored.LinkType -ne "Junction") { throw "Rollback did not recreate the junction" }
if ((Resolve-Path -LiteralPath ([string]$restored.Target)).Path -ne (Resolve-Path -LiteralPath $legacy).Path) { throw "Rollback junction target mismatch" }

Write-Output "CASE: existing directory"
$case = New-GameFixture -Name "directory"
$priorPath = Join-Path $case.game "mods\modAutoDriver\content\scripts\local\mod_autodriver.ws"
New-Item -ItemType Directory -Path (Split-Path -Parent $priorPath) -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $projectRoot "AGENT.md") -Destination $priorPath
$priorHash = Get-Sha256 $priorPath
& $deploy -GameRoot $case.game -UserInputPath $case.input -PackageManifestPath $manifest -ReceiptDirectory $case.receipts
if ((Get-Sha256 $priorPath) -ne $expectedPayloadHash) { throw "Directory deployment payload hash mismatch" }
$receipt = Get-LatestDeploymentReceipt $case.receipts
& $restore -ReceiptPath $receipt
if ((Get-Sha256 $priorPath) -ne $priorHash) { throw "Directory rollback did not restore the prior hash" }

Write-Output "CASE: clean install"
$case = New-GameFixture -Name "clean"
$cleanRuntime = Join-Path $case.game "mods\modAutoDriver"
& $deploy -GameRoot $case.game -UserInputPath $case.input -PackageManifestPath $manifest -ReceiptDirectory $case.receipts
$receipt = Get-LatestDeploymentReceipt $case.receipts
& $restore -ReceiptPath $receipt
if (Test-Path -LiteralPath $cleanRuntime) { throw "Clean-install rollback left a runtime directory" }

Write-Output "CASE: missing registration"
$case = New-GameFixture -Name "missing-registration"
Copy-Item -LiteralPath (Join-Path $projectRoot "AGENT.md") -Destination (Join-Path $case.game "mods\modBootstrap-registry\content\scripts\local\mods_registry.ws") -Force
Assert-Throws -Label "missing Bootstrap registration" -Operation {
    & $deploy -GameRoot $case.game -UserInputPath $case.input -PackageManifestPath $manifest -ReceiptDirectory $case.receipts -DryRun
}
if (Test-Path -LiteralPath (Join-Path $case.game "mods\modAutoDriver")) { throw "Missing-registration failure mutated runtime state" }

Write-Output "CASE: unexpected junction target"
$case = New-GameFixture -Name "unexpected-junction"
$actualTarget = Join-Path $case.root "actual-target"
$wrongTarget = Join-Path $case.root "wrong-target"
New-Item -ItemType Directory -Path $actualTarget,$wrongTarget | Out-Null
New-Item -ItemType Junction -Path (Join-Path $case.game "mods\modAutoDriver") -Target $actualTarget | Out-Null
$before = Get-FixtureFingerprint $case.root
Assert-Throws -Label "unexpected junction target" -Operation {
    & $deploy -GameRoot $case.game -UserInputPath $case.input -PackageManifestPath $manifest -ExpectedJunctionTarget $wrongTarget -ReceiptDirectory $case.receipts -DryRun
}
if ($before -ne (Get-FixtureFingerprint $case.root)) { throw "Unexpected-junction failure mutated fixture state" }

Write-Output "CASE: tampered package"
$case = New-GameFixture -Name "tampered-package"
$tamperedArtifact = Join-Path $case.root "artifact"
Copy-Item -LiteralPath (Split-Path -Parent $manifest) -Destination $tamperedArtifact -Recurse
$tamperedManifest = Join-Path $tamperedArtifact "package-manifest.json"
$tamperedPayload = Join-Path $tamperedArtifact "modAutoDriver\content\scripts\local\mod_autodriver.ws"
Copy-Item -LiteralPath (Join-Path $projectRoot "AGENT.md") -Destination $tamperedPayload -Force
Assert-Throws -Label "tampered package hash" -Operation {
    & $deploy -GameRoot $case.game -UserInputPath $case.input -PackageManifestPath $tamperedManifest -ReceiptDirectory $case.receipts -DryRun
}
if (Test-Path -LiteralPath (Join-Path $case.game "mods\modAutoDriver")) { throw "Tampered-package failure mutated runtime state" }

Write-Output "CASE: missing package manifest"
$case = New-GameFixture -Name "missing-package"
Assert-Throws -Label "missing package manifest" -Operation {
    & $deploy -GameRoot $case.game -UserInputPath $case.input -PackageManifestPath (Join-Path $case.root "missing-package-manifest.json") -ReceiptDirectory $case.receipts -DryRun
}
if (Test-Path -LiteralPath (Join-Path $case.game "mods\modAutoDriver")) { throw "Missing-package failure mutated runtime state" }

Write-Output "CASE: changed destination blocks rollback"
$case = New-GameFixture -Name "changed-destination"
& $deploy -GameRoot $case.game -UserInputPath $case.input -PackageManifestPath $manifest -ReceiptDirectory $case.receipts
$receipt = Get-LatestDeploymentReceipt $case.receipts
$changedPayload = Join-Path $case.game "mods\modAutoDriver\content\scripts\local\mod_autodriver.ws"
Copy-Item -LiteralPath (Join-Path $projectRoot "AGENT.md") -Destination $changedPayload -Force
Assert-Throws -Label "changed deployed payload" -Operation {
    & $restore -ReceiptPath $receipt
}
if ((Get-Sha256 $changedPayload) -ne (Get-Sha256 (Join-Path $projectRoot "AGENT.md"))) { throw "Blocked rollback mutated the changed payload" }

Write-Output "CASE: malformed and out-of-root receipts"
Assert-Throws -Label "malformed receipt" -Operation {
    & $restore -ReceiptPath (Join-Path $projectRoot "AGENT.md") -DryRun
}
$receiptObject = Get-Content -Raw -LiteralPath $receipt | ConvertFrom-Json
$receiptObject.runtimePath = Join-Path $case.root "outside-modAutoDriver"
$receiptObject.payloads[0].destination = Join-Path $case.root "outside-modAutoDriver\content\scripts\local\mod_autodriver.ws"
$unsafeReceipt = Join-Path $case.root "unsafe-receipt.json"
$receiptObject | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $unsafeReceipt -Encoding UTF8
Assert-Throws -Label "out-of-root receipt" -Operation {
    & $restore -ReceiptPath $unsafeReceipt -DryRun
}

Write-Output "ALL DEPLOYMENT TESTS PASSED"

[CmdletBinding()]
param()

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

$deploy = Join-Path $projectRoot "deploy.ps1"
$restore = Join-Path $projectRoot "restore-deployment.ps1"
$manifestPath = Join-Path $projectRoot "artifacts\Release\package-manifest.json"
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Create a clean Release package before running deployment tests."
}
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
$manifestDirectory = Split-Path -Parent $manifestPath
$autoPayload = @($manifest.payloads | Where-Object { $_.component -eq "AutoDriver" })[0]

function Get-Sha256 {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function New-GameFixture {
    param([string]$Name)
    $root = Join-Path $testRoot $Name
    $game = Join-Path $root "game"
    $input = Join-Path $root "profile\input.settings"
    New-Item -ItemType Directory -Path @(
        (Join-Path $game "bin\x64"),
        (Join-Path $game "bin\x64_dx12"),
        (Split-Path -Parent $input)
    ) -Force | Out-Null
    [System.IO.File]::WriteAllBytes((Join-Path $game "bin\x64\witcher3.exe"), [byte[]]@(1))
    [System.IO.File]::WriteAllBytes((Join-Path $game "bin\x64_dx12\witcher3.exe"), [byte[]]@(1))
    [System.IO.File]::WriteAllText($input, "[Exploration]`r`nIK_A=(Action=Jump)`r`n`r`n[Horse]`r`nIK_E=(Action=Mount)`r`n", [System.Text.UTF8Encoding]::new($false))
    return [ordered]@{
        root = $root
        game = $game
        input = $input
        receipts = Join-Path $root "receipts"
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

function Copy-PackageComponent {
    param([string]$Component, [string]$GameRoot)
    foreach ($payload in @($manifest.payloads | Where-Object { $_.component -eq $Component })) {
        $source = Join-Path $manifestDirectory $payload.packagePath
        $destination = Join-Path $GameRoot $payload.gameRelativePath
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $destination
    }
}

function Get-LatestDeploymentReceipt {
    param([string]$Directory)
    return (Get-ChildItem -LiteralPath $Directory -Filter "deployment-*.json" -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
}

function Assert-Throws {
    param([scriptblock]$Operation, [string]$Label)
    $threw = $false
    try { & $Operation }
    catch {
        $threw = $true
        Write-Output "EXPECTED FAILURE [$Label]: $($_.Exception.Message.Split("`n")[0])"
    }
    if (-not $threw) { throw "Expected failure did not occur: $Label" }
}

Write-Output "CASE: clean machine installs every required component"
$case = New-GameFixture -Name "clean"
$before = Get-FixtureFingerprint $case.root
& $deploy -GameRoot $case.game -UserInputPath $case.input -PackageManifestPath $manifestPath -ReceiptDirectory $case.receipts -DryRun
if ($before -ne (Get-FixtureFingerprint $case.root)) { throw "Clean-machine Dry Run changed fixture state" }
& $deploy -GameRoot $case.game -UserInputPath $case.input -PackageManifestPath $manifestPath -ReceiptDirectory $case.receipts
$deployedAutoDriver = Join-Path $case.game $autoPayload.gameRelativePath
if ((Get-Sha256 $deployedAutoDriver) -ne $autoPayload.sha256) { throw "Clean-machine AutoDriver hash mismatch" }
foreach ($component in @("BootstrapMod", "BootstrapDlc", "BootstrapRegistry")) {
    foreach ($payload in @($manifest.payloads | Where-Object { $_.component -eq $component })) {
        $destination = Join-Path $case.game $payload.gameRelativePath
        if (-not (Test-Path -LiteralPath $destination -PathType Leaf)) { throw "Clean-machine dependency missing: $destination" }
    }
}
$inputText = Get-Content -Raw -LiteralPath $case.input
foreach ($action in @("HorseWander", "WalkWander", "ToggleHorse", "GodMode", "OfficialTeleport", "RandomXYTeleport")) {
    if ($inputText -notmatch "AutoDriver_$action") { throw "Merged user input is missing AutoDriver_$action" }
}
$deployedFingerprint = Get-FixtureFingerprint $case.root
$secondDryRun = (& $deploy -GameRoot $case.game -UserInputPath $case.input -PackageManifestPath $manifestPath -ReceiptDirectory $case.receipts -DryRun 6>&1 | Out-String)
foreach ($expectedReuse in @("BootstrapMod: reuse", "BootstrapDlc: reuse", "BootstrapRegistry: reuse", "UserInput: reuse")) {
    if (-not $secondDryRun.Contains($expectedReuse)) { throw "Idempotent Dry Run did not report: $expectedReuse" }
}
if ($deployedFingerprint -ne (Get-FixtureFingerprint $case.root)) { throw "Idempotent Dry Run changed fixture state" }
$receipt = Get-LatestDeploymentReceipt $case.receipts
$beforeRollback = Get-FixtureFingerprint $case.root
& $restore -ReceiptPath $receipt -DryRun
if ($beforeRollback -ne (Get-FixtureFingerprint $case.root)) { throw "Rollback Dry Run changed fixture state" }
& $restore -ReceiptPath $receipt
if (Test-Path -LiteralPath (Join-Path $case.game "mods\modAutoDriver")) { throw "Clean rollback left AutoDriver" }
if (Test-Path -LiteralPath (Join-Path $case.game "mods\modBootstrap")) { throw "Clean rollback left installed modBootstrap" }
if (Test-Path -LiteralPath (Join-Path $case.game "dlc\dlcBootstrap")) { throw "Clean rollback left installed dlcBootstrap" }
if ((Get-Content -Raw -LiteralPath $case.input) -ne "[Exploration]`r`nIK_A=(Action=Jump)`r`n`r`n[Horse]`r`nIK_E=(Action=Mount)`r`n") { throw "Clean rollback did not restore user input" }

Write-Output "CASE: existing compatible Bootstrap is reused and registry is merged"
$case = New-GameFixture -Name "existing-bootstrap"
Copy-PackageComponent -Component "BootstrapMod" -GameRoot $case.game
Copy-PackageComponent -Component "BootstrapDlc" -GameRoot $case.game
$registryPath = Join-Path $case.game "mods\modBootstrap-registry\content\scripts\local\mods_registry.ws"
New-Item -ItemType Directory -Path (Split-Path -Parent $registryPath) -Force | Out-Null
$originalRegistry = "class CModRegistry extends CModFactory {`r`n    protected function createMods() {`r`n        add(createOtherMod());`r`n    }`r`n}`r`n"
[System.IO.File]::WriteAllText($registryPath, $originalRegistry, [System.Text.UTF8Encoding]::new($false))
$beforeGame = Get-FixtureFingerprint $case.game
$beforeInputHash = Get-Sha256 $case.input
& $deploy -GameRoot $case.game -UserInputPath $case.input -PackageManifestPath $manifestPath -ReceiptDirectory $case.receipts
$mergedRegistry = Get-Content -Raw -LiteralPath $registryPath
if ($mergedRegistry -notmatch 'add\(createOtherMod\(\)\);' -or ([regex]::Matches($mergedRegistry, 'add\(createAutoDriver\(\)\);')).Count -ne 1) {
    throw "Registry merge did not preserve existing registrations and add AutoDriver once"
}
$receipt = Get-LatestDeploymentReceipt $case.receipts
& $restore -ReceiptPath $receipt
if ((Get-FixtureFingerprint $case.game) -ne $beforeGame -or (Get-Sha256 $case.input) -ne $beforeInputHash) {
    throw "Existing-Bootstrap rollback did not restore the game and input fixture"
}

Write-Output "CASE: verified junction conversion still works"
$case = New-GameFixture -Name "junction"
Copy-PackageComponent -Component "BootstrapMod" -GameRoot $case.game
Copy-PackageComponent -Component "BootstrapDlc" -GameRoot $case.game
Copy-PackageComponent -Component "BootstrapRegistry" -GameRoot $case.game
$legacy = Join-Path $case.root "legacy-mod"
New-Item -ItemType Directory -Path (Join-Path $legacy "content\scripts\local") -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $projectRoot "content\scripts\local\mod_autodriver.ws") -Destination (Join-Path $legacy "content\scripts\local\mod_autodriver.ws")
New-Item -ItemType Junction -Path (Join-Path $case.game "mods\modAutoDriver") -Target $legacy | Out-Null
& $deploy -GameRoot $case.game -UserInputPath $case.input -PackageManifestPath $manifestPath -ExpectedJunctionTarget $legacy -ReceiptDirectory $case.receipts
if ((Get-Item -LiteralPath (Join-Path $case.game "mods\modAutoDriver") -Force).LinkType) { throw "Junction deployment did not create a real directory" }
$receipt = Get-LatestDeploymentReceipt $case.receipts
& $restore -ReceiptPath $receipt
$restored = Get-Item -LiteralPath (Join-Path $case.game "mods\modAutoDriver") -Force
if ([string]$restored.LinkType -ne "Junction") { throw "Rollback did not recreate the prior junction" }

Write-Output "CASE: changed installed Bootstrap is rejected before mutation"
$case = New-GameFixture -Name "changed-bootstrap"
Copy-PackageComponent -Component "BootstrapMod" -GameRoot $case.game
Copy-PackageComponent -Component "BootstrapDlc" -GameRoot $case.game
Copy-PackageComponent -Component "BootstrapRegistry" -GameRoot $case.game
$bootstrapFile = Join-Path $case.game "mods\modBootstrap\content\scripts\local\bootstrap\utils\basemod.ws"
[System.IO.File]::AppendAllText($bootstrapFile, "changed")
$before = Get-FixtureFingerprint $case.root
Assert-Throws -Label "changed Bootstrap" -Operation {
    & $deploy -GameRoot $case.game -UserInputPath $case.input -PackageManifestPath $manifestPath -ReceiptDirectory $case.receipts -DryRun
}
if ($before -ne (Get-FixtureFingerprint $case.root)) { throw "Changed-Bootstrap rejection mutated fixture" }

Write-Output "CASE: duplicate registry registration is rejected"
$case = New-GameFixture -Name "duplicate-registry"
Copy-PackageComponent -Component "BootstrapMod" -GameRoot $case.game
Copy-PackageComponent -Component "BootstrapDlc" -GameRoot $case.game
Copy-PackageComponent -Component "BootstrapRegistry" -GameRoot $case.game
$registryPath = Join-Path $case.game "mods\modBootstrap-registry\content\scripts\local\mods_registry.ws"
[System.IO.File]::AppendAllText($registryPath, "`r`nadd(createAutoDriver());`r`n")
$before = Get-FixtureFingerprint $case.root
Assert-Throws -Label "duplicate registration" -Operation {
    & $deploy -GameRoot $case.game -UserInputPath $case.input -PackageManifestPath $manifestPath -ReceiptDirectory $case.receipts -DryRun
}
if ($before -ne (Get-FixtureFingerprint $case.root)) { throw "Duplicate-registration rejection mutated fixture" }

Write-Output "CASE: tampered package is rejected"
$case = New-GameFixture -Name "tampered-package"
$tamperedArtifact = Join-Path $case.root "artifact"
Copy-Item -LiteralPath $manifestDirectory -Destination $tamperedArtifact -Recurse
$tamperedManifest = Join-Path $tamperedArtifact "package-manifest.json"
$tamperedObject = Get-Content -Raw -LiteralPath $tamperedManifest | ConvertFrom-Json
$tamperedPayload = @($tamperedObject.payloads | Where-Object { $_.component -eq "AutoDriver" })[0]
[System.IO.File]::AppendAllText((Join-Path $tamperedArtifact $tamperedPayload.packagePath), "changed")
Assert-Throws -Label "tampered package" -Operation {
    & $deploy -GameRoot $case.game -UserInputPath $case.input -PackageManifestPath $tamperedManifest -ReceiptDirectory $case.receipts -DryRun
}

Write-Output "CASE: post-deployment changes block rollback"
$case = New-GameFixture -Name "changed-after-deployment"
& $deploy -GameRoot $case.game -UserInputPath $case.input -PackageManifestPath $manifestPath -ReceiptDirectory $case.receipts
$receipt = Get-LatestDeploymentReceipt $case.receipts
[System.IO.File]::AppendAllText((Join-Path $case.game $autoPayload.gameRelativePath), "changed")
Assert-Throws -Label "changed deployed AutoDriver" -Operation { & $restore -ReceiptPath $receipt }

Write-Output "ALL DEPLOYMENT TESTS PASSED"

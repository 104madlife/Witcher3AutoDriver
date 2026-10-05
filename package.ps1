[CmdletBinding()]
param(
    [ValidateSet("Release", "Debug")]
    [string]$Configuration = "Release",
    [switch]$AllowDirty
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$projectRoot = $PSScriptRoot
$artifactRoot = [System.IO.Path]::GetFullPath((Join-Path $projectRoot "artifacts\$Configuration"))
$allowedRoot = [System.IO.Path]::GetFullPath((Join-Path $projectRoot "artifacts"))
$externalRoot = Join-Path $projectRoot "external\Bootstrap"
$externalGameRoot = Join-Path $externalRoot "game-root"
$dependencyMetadataPath = Join-Path $externalRoot "dependency.json"
$inputTemplatePath = Join-Path $projectRoot "modAutoDriver.input.settings"
$autoDriverSourcePath = Join-Path $projectRoot "content\scripts\local\mod_autodriver.ws"

if (-not $artifactRoot.StartsWith($allowedRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing artifact path outside the repository artifact root: $artifactRoot"
}

foreach ($required in @($autoDriverSourcePath, $inputTemplatePath, $dependencyMetadataPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Missing package input: $required"
    }
}

foreach ($required in @(
    (Join-Path $externalGameRoot "mods\modBootstrap"),
    (Join-Path $externalGameRoot "mods\modBootstrap-registry"),
    (Join-Path $externalGameRoot "dlc\dlcBootstrap")
)) {
    if (-not (Test-Path -LiteralPath $required -PathType Container)) {
        throw "Missing vendored Bootstrap component: $required"
    }
}

$sourceDirtyText = [string](git -C $projectRoot status --porcelain --untracked-files=all)
$sourceDirty = -not [string]::IsNullOrWhiteSpace($sourceDirtyText)
if ($sourceDirty -and -not $AllowDirty) {
    throw "Refusing to package a dirty source tree. Commit the intended changes or pass -AllowDirty for an explicitly non-release development package."
}

& (Join-Path $projectRoot "validate-project.ps1") -NoReceipt

if (Test-Path -LiteralPath $artifactRoot) {
    Remove-Item -LiteralPath $artifactRoot -Recurse -Force
}

$payloadDefinitions = [System.Collections.Generic.List[object]]::new()
$payloadDefinitions.Add([ordered]@{
    component = "AutoDriver"
    repositoryPath = "content\scripts\local\mod_autodriver.ws"
    sourcePath = $autoDriverSourcePath
    gameRelativePath = "mods\modAutoDriver\content\scripts\local\mod_autodriver.ws"
    deploymentPolicy = "replace-owned"
})

foreach ($file in Get-ChildItem -LiteralPath $externalGameRoot -Recurse -File | Sort-Object FullName) {
    $gameRelativePath = $file.FullName.Substring($externalGameRoot.Length).TrimStart('\')
    $component = if ($gameRelativePath.StartsWith("mods\modBootstrap-registry\", [System.StringComparison]::OrdinalIgnoreCase)) {
        "BootstrapRegistry"
    }
    elseif ($gameRelativePath.StartsWith("mods\modBootstrap\", [System.StringComparison]::OrdinalIgnoreCase)) {
        "BootstrapMod"
    }
    elseif ($gameRelativePath.StartsWith("dlc\dlcBootstrap\", [System.StringComparison]::OrdinalIgnoreCase)) {
        "BootstrapDlc"
    }
    else {
        throw "Unexpected file in vendored Bootstrap game-root payload: $gameRelativePath"
    }

    $payloadDefinitions.Add([ordered]@{
        component = $component
        repositoryPath = "external\Bootstrap\game-root\$gameRelativePath"
        sourcePath = $file.FullName
        gameRelativePath = $gameRelativePath
        deploymentPolicy = if ($component -eq "BootstrapRegistry") { "merge-registry" } else { "install-or-verify-shared" }
    })
}

$manifestPayloads = [System.Collections.Generic.List[object]]::new()
foreach ($definition in $payloadDefinitions) {
    $packageRelativePath = "game-root\$($definition.gameRelativePath)"
    $destinationPath = Join-Path $artifactRoot $packageRelativePath
    New-Item -ItemType Directory -Path (Split-Path -Parent $destinationPath) -Force | Out-Null
    Copy-Item -LiteralPath $definition.sourcePath -Destination $destinationPath

    $sourceHash = (Get-FileHash -LiteralPath $definition.sourcePath -Algorithm SHA256).Hash
    $destinationHash = (Get-FileHash -LiteralPath $destinationPath -Algorithm SHA256).Hash
    if ($sourceHash -ne $destinationHash) {
        throw "Packaged payload hash mismatch: source=$sourceHash destination=$destinationHash"
    }

    $manifestPayloads.Add([ordered]@{
        component = $definition.component
        repositoryPath = $definition.repositoryPath
        packagePath = $packageRelativePath
        gameRelativePath = $definition.gameRelativePath
        deploymentPolicy = $definition.deploymentPolicy
        bytes = (Get-Item -LiteralPath $destinationPath).Length
        sha256 = $destinationHash
    })
}

$packagedInputRelativePath = "configuration\modAutoDriver.input.settings"
$packagedInputPath = Join-Path $artifactRoot $packagedInputRelativePath
New-Item -ItemType Directory -Path (Split-Path -Parent $packagedInputPath) -Force | Out-Null
Copy-Item -LiteralPath $inputTemplatePath -Destination $packagedInputPath
$inputHash = (Get-FileHash -LiteralPath $packagedInputPath -Algorithm SHA256).Hash

$packagedGameFiles = @(Get-ChildItem -LiteralPath (Join-Path $artifactRoot "game-root") -Recurse -File)
if ($packagedGameFiles.Count -ne $manifestPayloads.Count) {
    throw "Portable package contains an unexpected number of game-root files: expected=$($manifestPayloads.Count) actual=$($packagedGameFiles.Count)"
}

$dependency = Get-Content -Raw -LiteralPath $dependencyMetadataPath | ConvertFrom-Json
$sourceCommit = (git -C $projectRoot rev-parse HEAD).Trim()
$manifest = [ordered]@{
    schemaVersion = 2
    kind = "witcher3-autodriver-portable-package"
    packagedAt = (Get-Date).ToString("o")
    configuration = $Configuration
    sourceCommit = $sourceCommit
    sourceDirty = $sourceDirty
    bootstrap = [ordered]@{
        name = $dependency.name
        version = $dependency.version
        sourceUrl = $dependency.sourceUrl
    }
    inputTemplate = [ordered]@{
        packagePath = $packagedInputRelativePath
        sha256 = $inputHash
    }
    payloads = @($manifestPayloads)
    note = "This package is intended for private installation. Packaging and repository validation do not prove WitcherScript compilation or gameplay behavior."
}

$manifestPath = Join-Path $artifactRoot "package-manifest.json"
$manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

$writtenManifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
if ($writtenManifest.schemaVersion -ne 2 -or $writtenManifest.payloads.Count -ne $manifestPayloads.Count) {
    throw "Package manifest verification failed."
}

Write-Output "Portable package created: $(Join-Path $artifactRoot 'game-root')"
Write-Output "Package manifest: $manifestPath"
Write-Output "Packaged game files: $($manifestPayloads.Count)"
Write-Output "Bootstrap version: $($dependency.version)"

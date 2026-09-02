[CmdletBinding()]
param(
    [ValidateSet("Release", "Debug")]
    [string]$Configuration = "Release",
    [switch]$AllowDirty
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$projectRoot = $PSScriptRoot
$sourceRelativePath = "content\scripts\local\mod_autodriver.ws"
$sourcePath = Join-Path $projectRoot $sourceRelativePath
$artifactRoot = [System.IO.Path]::GetFullPath((Join-Path $projectRoot "artifacts\$Configuration"))
$allowedRoot = [System.IO.Path]::GetFullPath((Join-Path $projectRoot "artifacts"))

if (-not $artifactRoot.StartsWith($allowedRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing artifact path outside the repository artifact root: $artifactRoot"
}

if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
    throw "Missing runtime source: $sourcePath"
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

$runtimeRoot = Join-Path $artifactRoot "modAutoDriver"
$destinationRelativePath = "modAutoDriver\content\scripts\local\mod_autodriver.ws"
$destinationPath = Join-Path $artifactRoot $destinationRelativePath
New-Item -ItemType Directory -Path (Split-Path -Parent $destinationPath) -Force | Out-Null
Copy-Item -LiteralPath $sourcePath -Destination $destinationPath

$sourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
$destinationHash = (Get-FileHash -LiteralPath $destinationPath -Algorithm SHA256).Hash
if ($sourceHash -ne $destinationHash) {
    throw "Packaged payload hash mismatch: source=$sourceHash destination=$destinationHash"
}

$packagedFiles = @(Get-ChildItem -LiteralPath $runtimeRoot -Recurse -File)
if ($packagedFiles.Count -ne 1 -or $packagedFiles[0].FullName -ne $destinationPath) {
    throw "Runtime package contains unexpected files."
}

$sourceCommit = (git -C $projectRoot rev-parse HEAD).Trim()
$manifest = [ordered]@{
    schemaVersion = 1
    kind = "witcher3-autodriver-runtime-package"
    packagedAt = (Get-Date).ToString("o")
    configuration = $Configuration
    projectRoot = $projectRoot
    sourceCommit = $sourceCommit
    sourceDirty = $sourceDirty
    runtimeDirectoryName = "modAutoDriver"
    payloads = @(
        [ordered]@{
            name = "mod_autodriver.ws"
            repositoryPath = $sourceRelativePath
            packagePath = $destinationRelativePath
            runtimeRelativePath = "content\scripts\local\mod_autodriver.ws"
            bytes = (Get-Item -LiteralPath $destinationPath).Length
            sha256 = $destinationHash
        }
    )
    exclusions = @(
        ".git",
        "documentation",
        "input templates",
        "Bootstrap",
        "StoryBoardUI",
        "vanilla scripts",
        "user settings"
    )
    note = "Packaging and repository validation do not prove WitcherScript compilation or gameplay behavior."
}

$manifestPath = Join-Path $artifactRoot "package-manifest.json"
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

$writtenManifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
if ($writtenManifest.payloads.Count -ne 1 -or $writtenManifest.payloads[0].sha256 -ne $destinationHash) {
    throw "Package manifest verification failed."
}

Write-Output "Package created: $runtimeRoot"
Write-Output "Package manifest: $manifestPath"
Write-Output "Payload SHA-256: $destinationHash"

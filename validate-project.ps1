[CmdletBinding()]
param(
    [string]$GameRoot,
    [string]$UserInputPath,
    [string]$OutputPath,
    [switch]$BaselinePreservation,
    [switch]$NoReceipt
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$projectRoot = $PSScriptRoot
$checks = [System.Collections.Generic.List[object]]::new()
$errors = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()

function Add-ValidationCheck {
    param(
        [string]$Name,
        [bool]$Passed,
        [string]$Detail,
        [ValidateSet("error", "warning", "info")]
        [string]$Severity = "error"
    )

    $checks.Add([ordered]@{
        name = $Name
        passed = $Passed
        severity = $Severity
        detail = $Detail
    })

    if (-not $Passed) {
        if ($Severity -eq "error") {
            $errors.Add("${Name}: ${Detail}")
        }
        elseif ($Severity -eq "warning") {
            $warnings.Add("${Name}: ${Detail}")
        }
    }
}

function Get-Sha256 {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Get-InputActionSummary {
    param([string]$Path)

    $contexts = [ordered]@{}
    $currentContext = "<global>"
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^\s*\[([^\]]+)\]\s*$') {
            $currentContext = $Matches[1]
            continue
        }

        if ($line -match 'Action\s*=\s*(AutoDriver_[A-Za-z0-9_]+)') {
            $action = $Matches[1]
            if (-not $contexts.Contains($action)) {
                $contexts[$action] = [System.Collections.Generic.List[string]]::new()
            }
            $contexts[$action].Add($currentContext)
        }
    }

    $summary = [System.Collections.Generic.List[object]]::new()
    foreach ($action in ($contexts.Keys | Sort-Object)) {
        $summary.Add([ordered]@{
            action = $action
            count = $contexts[$action].Count
            contexts = @($contexts[$action])
        })
    }
    return @($summary)
}

$requiredFiles = @(
    "content\scripts\local\mod_autodriver.ws",
    "modAutoDriver.input.settings",
    "PROJECT.md",
    "README.md",
    "docs\feature-dependency-audit.md",
    "docs\interface-matrix.md",
    "docs\experiments.md",
    "docs\pitfalls.md",
    "docs\standalone-migration-plan.md"
)

foreach ($relativePath in $requiredFiles) {
    $path = Join-Path $projectRoot $relativePath
    Add-ValidationCheck -Name "required:$relativePath" -Passed (Test-Path -LiteralPath $path -PathType Leaf) -Detail $path
}

$sourcePath = Join-Path $projectRoot "content\scripts\local\mod_autodriver.ws"
$source = if (Test-Path -LiteralPath $sourcePath) { Get-Content -Raw -LiteralPath $sourcePath } else { "" }
$factoryCount = ([regex]::Matches($source, 'function\s+createAutoDriver\s*\(\s*\)\s*:\s*CMod')).Count
$classCount = ([regex]::Matches($source, 'statemachine\s+class\s+CModAutoDriver\s+extends\s+CMod')).Count
Add-ValidationCheck -Name "factory:createAutoDriver" -Passed ($factoryCount -eq 1) -Detail "count=$factoryCount"
Add-ValidationCheck -Name "class:CModAutoDriver" -Passed ($classCount -eq 1) -Detail "count=$classCount"

$expectedActions = @(
    "AutoDriver_HorseWander",
    "AutoDriver_WalkWander",
    "AutoDriver_ToggleHorse",
    "AutoDriver_GodMode",
    "AutoDriver_OfficialTeleport",
    "AutoDriver_RandomXYTeleport"
)

$registeredActions = @(
    [regex]::Matches($source, "RegisterListener\s*\(\s*this\s*,\s*'[^']+'\s*,\s*'(AutoDriver_[^']+)'\s*\)") |
        ForEach-Object { $_.Groups[1].Value } |
        Sort-Object -Unique
)

foreach ($action in $expectedActions) {
    Add-ValidationCheck -Name "source-action:$action" -Passed ($registeredActions -contains $action) -Detail "registered=$($registeredActions -contains $action)"
}

$unexpectedActions = @($registeredActions | Where-Object { $expectedActions -notcontains $_ })
Add-ValidationCheck -Name "source-actions:unexpected" -Passed ($unexpectedActions.Count -eq 0) -Detail (($unexpectedActions -join ", ") -replace '^$', '<none>')

$inputSummaries = [ordered]@{}
$canonicalInputName = "modAutoDriver.input.settings"
foreach ($inputName in @($canonicalInputName)) {
    $inputPath = Join-Path $projectRoot $inputName
    if (-not (Test-Path -LiteralPath $inputPath)) {
        continue
    }

    $summary = @(Get-InputActionSummary -Path $inputPath)
    $inputSummaries[$inputName] = $summary
    $actions = @($summary | ForEach-Object { $_.action })
    foreach ($action in $expectedActions) {
        Add-ValidationCheck -Name "${inputName}:$action" -Passed ($actions -contains $action) -Detail "declared=$($actions -contains $action)"
    }

    $unexpectedInputActions = @($actions | Where-Object { $expectedActions -notcontains $_ })
    Add-ValidationCheck -Name "${inputName}:unexpected" -Passed ($unexpectedInputActions.Count -eq 0) -Detail (($unexpectedInputActions -join ", ") -replace '^$', '<none>')

    $horseWander = @($summary | Where-Object { $_.action -eq "AutoDriver_HorseWander" })
    $horseContexts = if ($horseWander.Count -eq 1) { @($horseWander[0].contexts) } else { @() }
    foreach ($context in @("Horse", "Horse_Replacer_Ciri")) {
        Add-ValidationCheck -Name "${inputName}:AutoDriver_HorseWander:$context" -Passed ($horseContexts -contains $context) -Detail "declared=$($horseContexts -contains $context)"
    }
}

$obsoleteInputPath = Join-Path $projectRoot "AutoDriver.input.settings"
Add-ValidationCheck -Name "input-template:single-canonical" -Passed (-not (Test-Path -LiteralPath $obsoleteInputPath)) -Detail "obsolete template absent=$(-not (Test-Path -LiteralPath $obsoleteInputPath))"

$storyboardReferences = @(
    [regex]::Matches($source, 'dlc\\modtemplates\\storyboardui\\[^"\r\n]+') |
        ForEach-Object { $_.Value } |
        Sort-Object -Unique
)
Add-ValidationCheck -Name "storyboard-resource-references" -Passed ($storyboardReferences.Count -eq 0) -Detail (($storyboardReferences -join ", ") -replace '^$', '<none>')

if ($BaselinePreservation) {
    $baseline = Get-Content -Raw -LiteralPath (Join-Path $projectRoot "baselines\legacy-current\manifest.json") | ConvertFrom-Json
    foreach ($entry in $baseline.trackedFiles) {
        if ($entry.path -notin @("content/scripts/local/mod_autodriver.ws", "AutoDriver.input.settings", "modAutoDriver.input.settings")) {
            continue
        }
        $path = Join-Path $projectRoot ($entry.path -replace '/', '\')
        $actual = if (Test-Path -LiteralPath $path) { Get-Sha256 $path } else { "<missing>" }
        Add-ValidationCheck -Name "baseline:$($entry.path)" -Passed ($actual -eq $entry.sha256) -Detail "expected=$($entry.sha256); actual=$actual"
    }
}

$gameEvidence = $null
if ($GameRoot) {
    $resolvedGameRoot = (Resolve-Path -LiteralPath $GameRoot).Path.TrimEnd('\')
    $gameEvidence = [ordered]@{
        root = $resolvedGameRoot
        executables = [System.Collections.Generic.List[object]]::new()
        runtimeDestination = $null
        bootstrapRegistrationCount = 0
    }

    foreach ($relativeExe in @("bin\x64\witcher3.exe", "bin\x64_dx12\witcher3.exe")) {
        $exePath = Join-Path $resolvedGameRoot $relativeExe
        $exists = Test-Path -LiteralPath $exePath -PathType Leaf
        Add-ValidationCheck -Name "game:$relativeExe" -Passed $exists -Detail $exePath
        if ($exists) {
            $item = Get-Item -LiteralPath $exePath
            $gameEvidence.executables.Add([ordered]@{
                path = $relativeExe
                version = $item.VersionInfo.FileVersion
                sha256 = Get-Sha256 $exePath
            })
        }
    }

    $bootstrapPath = Join-Path $resolvedGameRoot "mods\modBootstrap"
    Add-ValidationCheck -Name "dependency:modBootstrap" -Passed (Test-Path -LiteralPath $bootstrapPath -PathType Container) -Detail $bootstrapPath

    $registryPath = Join-Path $resolvedGameRoot "mods\modBootstrap-registry\content\scripts\local\mods_registry.ws"
    $registryExists = Test-Path -LiteralPath $registryPath -PathType Leaf
    Add-ValidationCheck -Name "dependency:bootstrap-registry" -Passed $registryExists -Detail $registryPath
    if ($registryExists) {
        $registry = Get-Content -Raw -LiteralPath $registryPath
        $registrationCount = ([regex]::Matches($registry, 'add\s*\(\s*createAutoDriver\s*\(\s*\)\s*\)\s*;')).Count
        $gameEvidence.bootstrapRegistrationCount = $registrationCount
        Add-ValidationCheck -Name "bootstrap:autoDriver-registration" -Passed ($registrationCount -eq 1) -Detail "count=$registrationCount"
    }

    $runtimePath = Join-Path $resolvedGameRoot "mods\modAutoDriver"
    if (Test-Path -LiteralPath $runtimePath) {
        $runtimeItem = Get-Item -LiteralPath $runtimePath -Force
        $target = if ($runtimeItem.Target) { [string]$runtimeItem.Target } else { $null }
        $gameEvidence.runtimeDestination = [ordered]@{
            path = $runtimePath
            kind = if ($runtimeItem.LinkType) { [string]$runtimeItem.LinkType } else { "directory" }
            target = $target
        }
        Add-ValidationCheck -Name "runtime-destination" -Passed $true -Detail "kind=$($gameEvidence.runtimeDestination.kind); target=$target" -Severity info
    }
    else {
        $gameEvidence.runtimeDestination = [ordered]@{ path = $runtimePath; kind = "absent"; target = $null }
        Add-ValidationCheck -Name "runtime-destination" -Passed $true -Detail "absent" -Severity info
    }
}

$liveInputEvidence = $null
if ($UserInputPath) {
    $inputExists = Test-Path -LiteralPath $UserInputPath -PathType Leaf
    Add-ValidationCheck -Name "user-input" -Passed $inputExists -Detail $UserInputPath
    if ($inputExists) {
        $liveSummary = @(Get-InputActionSummary -Path $UserInputPath)
        $liveActions = @($liveSummary | ForEach-Object { $_.action })
        foreach ($action in $expectedActions) {
            Add-ValidationCheck -Name "user-input:$action" -Passed ($liveActions -contains $action) -Detail "declared=$($liveActions -contains $action)"
        }
        $liveInputEvidence = [ordered]@{
            path = (Resolve-Path -LiteralPath $UserInputPath).Path
            sha256 = Get-Sha256 $UserInputPath
            actions = $liveSummary
        }
    }
}

$receipt = [ordered]@{
    schemaVersion = 1
    kind = "repository-validation"
    validatedAt = (Get-Date).ToString("o")
    projectRoot = $projectRoot
    sourceCommit = (git -C $projectRoot rev-parse HEAD).Trim()
    sourceDirty = [bool](git -C $projectRoot status --porcelain --untracked-files=all)
    baselinePreservation = [bool]$BaselinePreservation
    result = if ($errors.Count -eq 0) { "passed" } else { "failed" }
    checks = @($checks)
    registeredActions = $registeredActions
    inputTemplates = $inputSummaries
    storyboardReferences = $storyboardReferences
    game = $gameEvidence
    userInput = $liveInputEvidence
    warnings = @($warnings)
    errors = @($errors)
    note = "Repository validation does not prove WitcherScript compilation or gameplay behavior."
}

if (-not $NoReceipt) {
    if (-not $OutputPath) {
        $OutputPath = Join-Path $projectRoot "build\validation-receipt.json"
    }
    $resolvedOutput = [System.IO.Path]::GetFullPath($OutputPath)
    $outputDirectory = Split-Path -Parent $resolvedOutput
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    $receipt | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $resolvedOutput -Encoding UTF8
    Write-Output "Validation receipt: $resolvedOutput"
}

foreach ($warning in $warnings) {
    Write-Warning $warning
}

if ($errors.Count -gt 0) {
    throw "Repository validation failed:`n$($errors -join "`n")"
}

Write-Output "Repository validation passed. This is not a WitcherScript compile result."

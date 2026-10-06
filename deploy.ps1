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
$resolvedUserInputPath = [System.IO.Path]::GetFullPath($UserInputPath)

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

function Get-DirectoryState {
    param([string]$Path, [string]$Label)
    if (-not (Test-Path -LiteralPath $Path)) {
        return "absent"
    }
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.LinkType) {
        throw "$Label must not be a reparse point: $Path ($($item.LinkType))"
    }
    if (-not $item.PSIsContainer) {
        throw "$Label exists but is not a directory: $Path"
    }
    return "directory"
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

function Get-TextFileInfo {
    param([string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $offset = 0
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $encoding = [System.Text.UTF8Encoding]::new($true)
        $offset = 3
    }
    elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        $encoding = [System.Text.UnicodeEncoding]::new($false, $true)
        $offset = 2
    }
    elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
        $encoding = [System.Text.UnicodeEncoding]::new($true, $true)
        $offset = 2
    }
    else {
        $encoding = [System.Text.UTF8Encoding]::new($false)
    }
    $text = $encoding.GetString($bytes, $offset, $bytes.Length - $offset)
    return [ordered]@{
        text = $text
        encoding = $encoding
        newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    }
}

function Add-AutoDriverRegistration {
    param([string]$Text, [string]$Newline)
    $matches = [regex]::Matches($Text, 'add\s*\(\s*createAutoDriver\s*\(\s*\)\s*\)\s*;')
    if ($matches.Count -eq 1) {
        return $Text
    }
    if ($matches.Count -gt 1) {
        throw "Bootstrap registry contains duplicate AutoDriver registrations."
    }

    $functionMatch = [regex]::Match($Text, 'protected\s+function\s+createMods\s*\(\s*\)\s*\{')
    if (-not $functionMatch.Success) {
        throw "Bootstrap registry does not contain one recognizable createMods() function."
    }
    $openingBrace = $Text.IndexOf('{', $functionMatch.Index)
    $depth = 0
    $closingBrace = -1
    for ($i = $openingBrace; $i -lt $Text.Length; $i += 1) {
        if ($Text[$i] -eq '{') { $depth += 1 }
        elseif ($Text[$i] -eq '}') {
            $depth -= 1
            if ($depth -eq 0) {
                $closingBrace = $i
                break
            }
        }
    }
    if ($closingBrace -lt 0) {
        throw "Bootstrap registry createMods() braces are malformed."
    }

    $lineStart = $Text.LastIndexOf($Newline, $closingBrace, [System.StringComparison]::Ordinal)
    if ($lineStart -lt 0) {
        $lineStart = 0
    }
    else {
        $lineStart += $Newline.Length
    }
    $closingIndent = $Text.Substring($lineStart, $closingBrace - $lineStart)
    $insertion = "$closingIndent    add(createAutoDriver());$Newline"
    return $Text.Insert($lineStart, $insertion)
}

function Merge-AutoDriverInput {
    param([string]$CurrentText, [string]$TemplateText, [string]$Newline)
    $bindings = [ordered]@{}
    $section = $null
    foreach ($line in ($TemplateText -split '\r?\n')) {
        if ($line -match '^\s*\[([^\]]+)\]\s*$') {
            $section = $Matches[1]
            if (-not $bindings.Contains($section)) {
                $bindings[$section] = [System.Collections.Generic.List[string]]::new()
            }
        }
        elseif ($section -and $line -match 'Action\s*=\s*AutoDriver_[A-Za-z0-9_]+') {
            $bindings[$section].Add($line.Trim())
        }
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($line in ($CurrentText -split '\r?\n')) {
        if ($line -notmatch 'Action\s*=\s*AutoDriver_[A-Za-z0-9_]+') {
            $lines.Add($line)
        }
    }
    while ($lines.Count -gt 0 -and [string]::IsNullOrWhiteSpace($lines[$lines.Count - 1])) {
        $lines.RemoveAt($lines.Count - 1)
    }

    foreach ($sectionName in $bindings.Keys) {
        $header = "[$sectionName]"
        $headerIndex = -1
        for ($i = 0; $i -lt $lines.Count; $i += 1) {
            if ($lines[$i].Trim() -eq $header) {
                $headerIndex = $i
                break
            }
        }
        if ($headerIndex -lt 0) {
            if ($lines.Count -gt 0) { $lines.Add("") }
            $lines.Add($header)
            $headerIndex = $lines.Count - 1
        }
        $insertAt = $headerIndex + 1
        foreach ($binding in $bindings[$sectionName]) {
            $lines.Insert($insertAt, $binding)
            $insertAt += 1
        }
    }

    return (($lines -join $Newline).TrimEnd("`r", "`n") + $Newline)
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

foreach ($required in @(
    (Join-Path $resolvedGameRoot "bin\x64\witcher3.exe"),
    (Join-Path $resolvedGameRoot "bin\x64_dx12\witcher3.exe")
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

& (Join-Path $projectRoot "validate-project.ps1") -NoReceipt

if (-not $PackageManifestPath) {
    $PackageManifestPath = Join-Path $projectRoot "artifacts\$Configuration\package-manifest.json"
}
if (-not (Test-Path -LiteralPath $PackageManifestPath -PathType Leaf)) {
    throw "Missing package manifest: $PackageManifestPath"
}

$resolvedManifestPath = (Resolve-Path -LiteralPath $PackageManifestPath).Path
$manifestDirectory = Split-Path -Parent $resolvedManifestPath
$manifest = Get-Content -Raw -LiteralPath $resolvedManifestPath | ConvertFrom-Json
if ($manifest.schemaVersion -ne 2 -or $manifest.kind -ne "witcher3-autodriver-portable-package") {
    throw "Unsupported package manifest: $resolvedManifestPath"
}
if ($manifest.sourceDirty) {
    throw "Refusing to deploy a package produced from a dirty source tree."
}

$verifiedPayloads = [System.Collections.Generic.List[object]]::new()
foreach ($payload in $manifest.payloads) {
    $packagePath = Assert-ChildPath -Path (Join-Path $manifestDirectory $payload.packagePath) -Parent $manifestDirectory -Label "Package payload"
    if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) {
        throw "Missing package payload: $packagePath"
    }
    $packageHash = Get-Sha256 $packagePath
    if ($packageHash -ne $payload.sha256) {
        throw "Package payload hash mismatch: expected=$($payload.sha256) actual=$packageHash path=$packagePath"
    }
    $destination = Assert-ChildPath -Path (Join-Path $resolvedGameRoot $payload.gameRelativePath) -Parent $resolvedGameRoot -Label "Game payload"
    $verifiedPayloads.Add([ordered]@{
        component = [string]$payload.component
        packagePath = $packagePath
        destination = $destination
        gameRelativePath = [string]$payload.gameRelativePath
        sha256 = [string]$payload.sha256
    })
}

$autoPayloads = @($verifiedPayloads | Where-Object { $_.component -eq "AutoDriver" })
$registryPayloads = @($verifiedPayloads | Where-Object { $_.component -eq "BootstrapRegistry" })
if ($autoPayloads.Count -ne 1 -or $registryPayloads.Count -ne 1) {
    throw "Package must contain exactly one AutoDriver payload and one Bootstrap registry payload."
}
$autoPayload = $autoPayloads[0]
$registryPayload = $registryPayloads[0]

$dependencyPlans = [System.Collections.Generic.List[object]]::new()
foreach ($definition in @(
    [ordered]@{ component = "BootstrapMod"; root = (Join-Path $resolvedGameRoot "mods\modBootstrap") },
    [ordered]@{ component = "BootstrapDlc"; root = (Join-Path $resolvedGameRoot "dlc\dlcBootstrap") }
)) {
    $componentPayloads = @($verifiedPayloads | Where-Object { $_.component -eq $definition.component })
    if ($componentPayloads.Count -eq 0) {
        throw "Package does not contain component: $($definition.component)"
    }
    $state = Get-DirectoryState -Path $definition.root -Label $definition.component
    if ($state -eq "directory") {
        foreach ($payload in $componentPayloads) {
            if (-not (Test-Path -LiteralPath $payload.destination -PathType Leaf)) {
                throw "Installed $($definition.component) is incomplete; missing: $($payload.destination)"
            }
            $installedHash = Get-Sha256 $payload.destination
            if ($installedHash -ne $payload.sha256) {
                throw "Installed $($definition.component) differs from the vendored version: $($payload.destination)"
            }
        }
    }
    $dependencyPlans.Add([ordered]@{
        component = $definition.component
        root = $definition.root
        mode = if ($state -eq "absent") { "install" } else { "reuse" }
        payloads = $componentPayloads
    })
}

$registryPath = $registryPayload.destination
$registryExists = Test-Path -LiteralPath $registryPath -PathType Leaf
$registryMode = if (-not $registryExists) { "create" } else { "reuse" }
$registryDesiredText = $null
$registryTextInfo = $null
if ($registryExists) {
    $registryTextInfo = Get-TextFileInfo -Path $registryPath
    $registrationCount = ([regex]::Matches($registryTextInfo.text, 'add\s*\(\s*createAutoDriver\s*\(\s*\)\s*\)\s*;')).Count
    if ($registrationCount -gt 1) {
        throw "Installed Bootstrap registry contains duplicate AutoDriver registrations."
    }
    if ($registrationCount -eq 0) {
        $registryMode = "update"
        $registryDesiredText = Add-AutoDriverRegistration -Text $registryTextInfo.text -Newline $registryTextInfo.newline
    }
}

$inputTemplatePath = Assert-ChildPath -Path (Join-Path $manifestDirectory $manifest.inputTemplate.packagePath) -Parent $manifestDirectory -Label "Input template"
if (-not (Test-Path -LiteralPath $inputTemplatePath -PathType Leaf) -or (Get-Sha256 $inputTemplatePath) -ne $manifest.inputTemplate.sha256) {
    throw "Packaged AutoDriver input template is missing or has the wrong hash."
}
$inputTemplateText = (Get-TextFileInfo -Path $inputTemplatePath).text
$inputExists = Test-Path -LiteralPath $resolvedUserInputPath -PathType Leaf
$inputTextInfo = if ($inputExists) { Get-TextFileInfo -Path $resolvedUserInputPath } else { [ordered]@{ text = ""; encoding = [System.Text.UTF8Encoding]::new($false); newline = "`r`n" } }
$inputDesiredText = Merge-AutoDriverInput -CurrentText $inputTextInfo.text -TemplateText $inputTemplateText -Newline $inputTextInfo.newline
$inputMode = if (-not $inputExists) { "create" } elseif ($inputDesiredText -cne $inputTextInfo.text) { "update" } else { "reuse" }

$runtimeState = Get-RuntimeState -Path $runtimePath
if ($runtimeState.kind -eq "junction") {
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
$autoPreviousExists = Test-Path -LiteralPath $autoPayload.destination -PathType Leaf
$autoPreviousHash = if ($autoPreviousExists) { Get-Sha256 $autoPayload.destination } else { $null }
$autoBackupPath = if ($runtimeState.kind -eq "directory" -and $autoPreviousExists) { Join-Path $backupDirectory "AutoDriver\mod_autodriver.ws" } else { $null }
$registryPreviousHash = if ($registryExists) { Get-Sha256 $registryPath } else { $null }
$registryBackupPath = if ($registryMode -eq "update") { Join-Path $backupDirectory "BootstrapRegistry\mods_registry.ws" } else { $null }
$inputPreviousHash = if ($inputExists) { Get-Sha256 $resolvedUserInputPath } else { $null }
$inputBackupPath = if ($inputMode -eq "update") { Join-Path $backupDirectory "UserInput\input.settings" } else { $null }

Write-Output "AutoDriver runtime mode: $($runtimeState.kind)"
foreach ($plan in $dependencyPlans) {
    Write-Output "$($plan.component): $($plan.mode)"
}
Write-Output "BootstrapRegistry: $registryMode"
Write-Output "UserInput: $inputMode"
Write-Output "AutoDriver destination: $($autoPayload.destination)"
Write-Output "Receipt: $receiptPath"
if ($DryRun) {
    Write-Output "Dry Run complete. No filesystem changes were made."
    exit 0
}

$installedDependencyPlans = [System.Collections.Generic.List[object]]::new()
$registryWritten = $false
$inputWritten = $false
$junctionRemoved = $false
$runtimeCreated = $false
$autoWritten = $false

try {
    foreach ($plan in $dependencyPlans) {
        if ($plan.mode -ne "install") { continue }
        New-Item -ItemType Directory -Path $plan.root -Force | Out-Null
        foreach ($payload in $plan.payloads) {
            New-Item -ItemType Directory -Path (Split-Path -Parent $payload.destination) -Force | Out-Null
            Copy-Item -LiteralPath $payload.packagePath -Destination $payload.destination
            if ((Get-Sha256 $payload.destination) -ne $payload.sha256) {
                throw "Installed dependency hash mismatch: $($payload.destination)"
            }
        }
        $installedDependencyPlans.Add($plan)
    }

    if ($registryMode -eq "create") {
        New-Item -ItemType Directory -Path (Split-Path -Parent $registryPath) -Force | Out-Null
        Copy-Item -LiteralPath $registryPayload.packagePath -Destination $registryPath
        $registryWritten = $true
    }
    elseif ($registryMode -eq "update") {
        New-Item -ItemType Directory -Path (Split-Path -Parent $registryBackupPath) -Force | Out-Null
        Copy-Item -LiteralPath $registryPath -Destination $registryBackupPath
        [System.IO.File]::WriteAllText($registryPath, $registryDesiredText, $registryTextInfo.encoding)
        $registryWritten = $true
    }
    $registryDeployedHash = Get-Sha256 $registryPath
    $deployedRegistryText = (Get-TextFileInfo -Path $registryPath).text
    $deployedRegistrationCount = ([regex]::Matches($deployedRegistryText, 'add\s*\(\s*createAutoDriver\s*\(\s*\)\s*\)\s*;')).Count
    if ($deployedRegistrationCount -ne 1) {
        throw "Bootstrap registry deployment did not produce exactly one AutoDriver registration."
    }

    if ($inputMode -eq "update") {
        New-Item -ItemType Directory -Path (Split-Path -Parent $inputBackupPath) -Force | Out-Null
        Copy-Item -LiteralPath $resolvedUserInputPath -Destination $inputBackupPath
    }
    if ($inputMode -ne "reuse") {
        New-Item -ItemType Directory -Path (Split-Path -Parent $resolvedUserInputPath) -Force | Out-Null
        [System.IO.File]::WriteAllText($resolvedUserInputPath, $inputDesiredText, $inputTextInfo.encoding)
        $inputWritten = $true
    }
    $inputDeployedHash = Get-Sha256 $resolvedUserInputPath

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

    if ($autoBackupPath) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $autoBackupPath) -Force | Out-Null
        Copy-Item -LiteralPath $autoPayload.destination -Destination $autoBackupPath
        if ((Get-Sha256 $autoBackupPath) -ne $autoPreviousHash) {
            throw "AutoDriver backup hash verification failed."
        }
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $autoPayload.destination) -Force | Out-Null
    Copy-Item -LiteralPath $autoPayload.packagePath -Destination $autoPayload.destination -Force
    $autoWritten = $true
    $autoDeployedHash = Get-Sha256 $autoPayload.destination
    if ($autoDeployedHash -ne $autoPayload.sha256) {
        throw "Deployed AutoDriver hash mismatch: expected=$($autoPayload.sha256) actual=$autoDeployedHash"
    }

    & (Join-Path $projectRoot "validate-project.ps1") -GameRoot $resolvedGameRoot -UserInputPath $resolvedUserInputPath -NoReceipt

    $dependencyReceipt = @($dependencyPlans | ForEach-Object {
        [ordered]@{
            component = $_.component
            root = $_.root
            mode = $_.mode
            files = @($_.payloads | ForEach-Object {
                [ordered]@{ destination = $_.destination; sha256 = $_.sha256 }
            })
        }
    })
    $receipt = [ordered]@{
        schemaVersion = 2
        kind = "witcher3-autodriver-deployment"
        deploymentId = $timestamp
        deployedAt = (Get-Date).ToString("o")
        sourceCommit = $manifest.sourceCommit
        gameRoot = $resolvedGameRoot
        runtimePath = $runtimePath
        previousRuntime = $runtimeState
        packageManifest = [ordered]@{ path = $resolvedManifestPath; sha256 = Get-Sha256 $resolvedManifestPath }
        payloads = @([ordered]@{
            name = "mod_autodriver.ws"
            destination = $autoPayload.destination
            deployedSha256 = $autoDeployedHash
            previousExists = $autoPreviousExists
            previousSha256 = $autoPreviousHash
            backup = $autoBackupPath
        })
        dependencies = $dependencyReceipt
        bootstrapRegistry = [ordered]@{
            path = $registryPath
            mode = $registryMode
            previousSha256 = $registryPreviousHash
            deployedSha256 = $registryDeployedHash
            backup = $registryBackupPath
        }
        userInput = [ordered]@{
            path = $resolvedUserInputPath
            mode = $inputMode
            previousSha256 = $inputPreviousHash
            deployedSha256 = $inputDeployedHash
            backup = $inputBackupPath
        }
        result = "passed"
    }

    New-Item -ItemType Directory -Path $resolvedReceiptDirectory -Force | Out-Null
    $receipt | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $receiptPath -Encoding UTF8
    $verifiedReceipt = Get-Content -Raw -LiteralPath $receiptPath | ConvertFrom-Json
    if ($verifiedReceipt.result -ne "passed" -or $verifiedReceipt.payloads[0].deployedSha256 -ne $autoDeployedHash) {
        throw "Deployment receipt verification failed."
    }
    Write-Output "Deployment passed. Receipt: $receiptPath"
}
catch {
    $failure = $_
    try {
        if ($autoWritten -and (Test-Path -LiteralPath $autoPayload.destination -PathType Leaf)) {
            if ($runtimeState.kind -eq "directory" -and $autoPreviousExists -and $autoBackupPath -and (Test-Path -LiteralPath $autoBackupPath -PathType Leaf)) {
                Copy-Item -LiteralPath $autoBackupPath -Destination $autoPayload.destination -Force
            }
            else {
                Remove-Item -LiteralPath $autoPayload.destination -Force
                Remove-EmptyParents -StartPath (Split-Path -Parent $autoPayload.destination) -StopRoot $runtimePath -RemoveStopRoot ($runtimeState.kind -ne "directory")
            }
        }
        elseif ($runtimeCreated -and (Test-Path -LiteralPath $runtimePath -PathType Container) -and (Get-ChildItem -LiteralPath $runtimePath -Force | Measure-Object).Count -eq 0) {
            [System.IO.Directory]::Delete($runtimePath, $false)
        }
        if ($junctionRemoved -and -not (Test-Path -LiteralPath $runtimePath)) {
            New-Item -ItemType Junction -Path $runtimePath -Target $runtimeState.target | Out-Null
        }

        if ($inputWritten) {
            if ($inputMode -eq "update") { Copy-Item -LiteralPath $inputBackupPath -Destination $resolvedUserInputPath -Force }
            elseif ($inputMode -eq "create" -and (Test-Path -LiteralPath $resolvedUserInputPath -PathType Leaf)) { Remove-Item -LiteralPath $resolvedUserInputPath -Force }
        }
        if ($registryWritten) {
            if ($registryMode -eq "update") { Copy-Item -LiteralPath $registryBackupPath -Destination $registryPath -Force }
            elseif ($registryMode -eq "create" -and (Test-Path -LiteralPath $registryPath -PathType Leaf)) {
                Remove-Item -LiteralPath $registryPath -Force
                Remove-EmptyParents -StartPath (Split-Path -Parent $registryPath) -StopRoot (Join-Path $resolvedGameRoot "mods\modBootstrap-registry") -RemoveStopRoot $true
            }
        }
        foreach ($plan in @($installedDependencyPlans | Sort-Object { $_.root.Length } -Descending)) {
            foreach ($payload in @($plan.payloads | Sort-Object { $_.destination.Length } -Descending)) {
                if (Test-Path -LiteralPath $payload.destination -PathType Leaf) { Remove-Item -LiteralPath $payload.destination -Force }
            }
            Remove-EmptyParents -StartPath $plan.root -StopRoot $plan.root -RemoveStopRoot $true
        }
    }
    catch {
        Write-Warning "Automatic rollback also failed: $($_.Exception.Message)"
    }
    throw $failure
}

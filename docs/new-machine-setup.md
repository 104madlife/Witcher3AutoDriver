# New-machine AutoDriver setup for an AI operator

This procedure is written for an AI configuring AutoDriver from a private checkout. Do not invent paths and do not reuse paths recorded in historical migration receipts.

## 1. Locate the two machine-specific paths

Determine the Witcher 3 game root. A valid root contains all of these paths:

```text
bin/x64/witcher3.exe
bin/x64_dx12/witcher3.exe
```

The `mods` and `dlc` directories may be absent on a clean game installation; deployment creates the required component paths.

The game may be installed through Steam or GOG and may be in a non-default library. Search known game libraries first. If more than one valid installation exists or none can be identified confidently, ask the user which game root to use.

Determine the live user input path. Start from the operating system's Documents known folder rather than assuming a drive or username:

```powershell
$documents = [Environment]::GetFolderPath("MyDocuments")
$userInputPath = Join-Path $documents "The Witcher 3\input.settings"
```

Documents may be redirected to OneDrive. If the expected file is absent, search the current user's Documents and OneDrive Documents locations. Ask the user when more than one active profile is plausible. The deployment script can create a missing `input.settings`, but using the wrong profile would make the hotkeys unavailable.

Assign the selected paths only for the current PowerShell session:

```powershell
$gameRoot = "<selected Witcher 3 game root>"
$userInputPath = "<selected active input.settings path>"
```

Do not commit those values.

## 2. Preflight

From the repository root:

```powershell
git status --short
.\validate-project.ps1 -NoReceipt
```

The release package requires a clean Git tree. If the tree is dirty, inspect the changes; do not discard or overwrite work merely to make packaging pass.

Make sure `witcher3` and `REDlauncher` are not running before the real deployment.

## 3. Build the private portable package

```powershell
.\package.ps1
```

This creates `artifacts/Release/game-root` and a hash manifest. The package includes Bootstrap because the current AutoDriver class inherits `CMod` and is instantiated through `CModRegistry`.

## 4. Preview deployment

```powershell
.\deploy.ps1 `
  -GameRoot $gameRoot `
  -UserInputPath $userInputPath `
  -DryRun
```

Interpret the reported modes:

- `BootstrapMod: install` and `BootstrapDlc: install` are expected on a clean machine.
- `reuse` means the installed files match the bundled version exactly.
- `BootstrapRegistry: create` installs the bundled clean registry.
- `BootstrapRegistry: update` preserves the existing registry and adds AutoDriver.
- `UserInput: create` or `update` installs the canonical AutoDriver bindings.

If deployment reports that an installed Bootstrap file differs, stop and report the exact path. Do not delete, replace, merge, or downgrade it automatically; another Mod may depend on that installation.

If `mods/modAutoDriver` is a junction, inspect its target and rerun the command with `-ExpectedJunctionTarget` set to that exact verified target.

## 5. Deploy and retain the receipt

Run the same command without `-DryRun`:

```powershell
.\deploy.ps1 `
  -GameRoot $gameRoot `
  -UserInputPath $userInputPath
```

Keep the reported JSON receipt under `build/deployments`. It records installed versus reused dependencies, backups, and hashes needed for a safe rollback.

After deployment, run:

```powershell
.\validate-project.ps1 `
  -GameRoot $gameRoot `
  -UserInputPath $userInputPath `
  -NoReceipt
```

## 6. Game validation

Launch the game and require all of the following:

1. WitcherScript compilation succeeds.
2. The AutoDriver loaded HUD message appears once.
3. NumPad2/3/6/7/8/9 reach their handlers.
4. Loading another save or fast travelling does not create duplicate callbacks.

Record the exact compiler error and stop gameplay testing if compilation fails.

## 7. Rollback

Exit the game and launcher, then run:

```powershell
.\restore-deployment.ps1 -ReceiptPath "<exact deployment receipt>"
```

Rollback refuses to overwrite files changed after deployment. It removes Bootstrap only when the receipt proves that the same deployment installed it; otherwise the shared dependency remains untouched.

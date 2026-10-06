# The Witcher 3 AutoDriver

AutoDriver is a WitcherScript state-machine Mod used for automated character, horse, protection, and teleport experiments in The Witcher 3.

This private repository contains the AutoDriver source and its verified Bootstrap 0.5 Next-Gen runtime dependency. The game-facing runtime name remains `modAutoDriver`.

## Runtime contents

- `mods/modAutoDriver`: AutoDriver WitcherScript.
- `mods/modBootstrap`: the `CMod` base, logger, loader, and Bootstrap utilities.
- `mods/modBootstrap-registry`: shared Bootstrap registry containing one `add(createAutoDriver());` registration.
- `dlc/dlcBootstrap`: Bootstrap startup entity and DLC resources.
- AutoDriver bindings merged into the user's `input.settings` during deployment.

StoryBoardUI, RadishSeeds, and SharedImports are not required.

The vendored Bootstrap files came from [Community Patch - Bootstrap and Utilities](https://www.nexusmods.com/witcher3/mods/2109). Its upstream permissions prohibit redistribution on other sites without permission. Keep this repository and packages containing `external/Bootstrap` private unless the author grants permission.

## New-machine setup

An AI configuring another machine should follow [docs/new-machine-setup.md](docs/new-machine-setup.md). It must determine or ask for:

1. the Witcher 3 game root containing `bin`, `mods`, and `dlc`;
2. the active user's `Documents/The Witcher 3/input.settings` path, accounting for redirected or OneDrive Documents folders.

No repository script contains a machine-specific game or profile path.

## Repository validation

Validation checks AutoDriver, the vendored Bootstrap payload, input coverage, and—when paths are supplied—the target installation:

```powershell
.\validate-project.ps1

.\validate-project.ps1 `
  -GameRoot $gameRoot `
  -UserInputPath $userInputPath
```

## Package

Create the complete private installation package without touching the game:

```powershell
.\package.ps1
```

The generated `artifacts/Release/game-root` tree contains:

```text
game-root/
├── mods/
│   ├── modAutoDriver/
│   ├── modBootstrap/
│   └── modBootstrap-registry/
└── dlc/
    └── dlcBootstrap/
```

Every packaged game file is recorded with its SHA-256 value in `package-manifest.json`.

## Safe deployment

Preview the complete transaction first:

```powershell
.\deploy.ps1 `
  -GameRoot $gameRoot `
  -UserInputPath $userInputPath `
  -DryRun
```

After reviewing the preview, run the same command without `-DryRun`.

Deployment performs these operations transactionally:

- installs the bundled Bootstrap Mod and DLC when absent;
- reuses an installed Bootstrap only when all expected files match the bundled version;
- installs a missing registry or adds exactly one AutoDriver registration to an existing registry without removing other Mods;
- deploys the AutoDriver runtime directory;
- removes stale AutoDriver bindings and merges the canonical bindings into the live user input file;
- records backups and hashes in a deployment receipt.

The script stops before mutation when an installed Bootstrap file differs, a registry is malformed, a package hash is wrong, or the game is running.

## Rollback

Exit the game, then use the exact deployment receipt:

```powershell
.\restore-deployment.ps1 -ReceiptPath $deploymentReceipt
```

Rollback restores the previous AutoDriver runtime, registry, and user input. Bootstrap components are removed only when that deployment installed them; pre-existing compatible Bootstrap components are retained.

## Compilation and runtime acceptance

The authoritative compile gate is the game's script compilation at launch. After deployment, launch the game and verify the AutoDriver startup message plus NumPad2/3/6/7/8/9. Repository validation, packaging, and sandbox tests cannot replace this game run.

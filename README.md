# The Witcher 3 AutoDriver

AutoDriver is a WitcherScript state-machine Mod used for automated character, horse, camera, protection, and teleport experiments in The Witcher 3.

This repository is the standalone development source. The game-facing runtime name remains `modAutoDriver`.

## Runtime dependencies

- The Witcher 3 Next-Gen 4.x installation.
- `modBootstrap` and `modBootstrap-registry`.
- Exactly one `add(createAutoDriver());` registration in the effective Bootstrap registry.
- User input bindings for the `AutoDriver_*` actions.
- `modStoryboardUi` plus `dlcStoryboardUi` for the camera and Geralt-clone features.

Bootstrap, StoryBoardUI, vanilla scripts, and the user's `input.settings` are external dependencies. This repository does not vendor or overwrite them.

## Repository validation

Validation is read-only and does not claim that WitcherScript compiles:

```powershell
.\validate-project.ps1

.\validate-project.ps1 `
  -GameRoot "E:\SteamLibrary\steamapps\common\The Witcher 3" `
  -UserInputPath "C:\Users\64617\Documents\The Witcher 3\input.settings"
```

## Package

Create the runtime-only package without touching the game installation:

```powershell
.\package.ps1
```

Expected runtime payload:

```text
artifacts\Release\modAutoDriver\content\scripts\local\mod_autodriver.ws
```

## Safe deployment

Always preview the transaction first:

```powershell
.\deploy.ps1 `
  -GameRoot "E:\SteamLibrary\steamapps\common\The Witcher 3" `
  -UserInputPath "C:\Users\64617\Documents\The Witcher 3\input.settings" `
  -DryRun
```

After reviewing the preview, deploy with the same command without `-DryRun`. The first deployment can replace the verified legacy `modAutoDriver` junction with a real runtime-only directory. It does not modify the junction target.

Deployment does not edit Bootstrap registration or user input. Those integrations must already be present.

## Rollback

Exit the game, then use the exact deployment receipt:

```powershell
.\restore-deployment.ps1 -ReceiptPath "<deployment-receipt.json>"
```

For the first migration deployment, rollback removes only the verified deployed payload and recreates the prior junction. Later deployments restore only receipt-owned files.

## Compilation and runtime acceptance

No standalone WitcherScript compiler was found during migration. The authoritative compile gate is the game's script compilation at launch. Repository validation and packaging success do not prove gameplay behavior.

See [docs/standalone-migration-plan.md](docs/standalone-migration-plan.md) for the evidence boundary, deployment design, rollback rules, and complete NumPad2–9 acceptance checklist.

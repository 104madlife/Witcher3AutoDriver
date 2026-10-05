# AutoDriver

Created: 2026-05-26
Knowledge scaffold adopted: 2026-08-15

## Project Context

- Game: The Witcher 3
- Purpose: drive character, horse, protection, and teleport state changes for automated in-game visual-data collection experiments.
- Mod form: WitcherScript content Mod implemented as a bootstrapped `CMod` state machine.
- Source entry point: `content/scripts/local/mod_autodriver.ws`.
- Current status: standalone repository conversion, runtime-only packaging, transactional sandbox deployment/rollback, and real-game-root Dry Run are complete. The user confirmed game compilation and remaining hotkeys after NumPad4/5 removal. The later input consolidation and unreachable-experiment cleanup require one fresh game validation, and the first real directory deployment is pending.
- Mod identity in source: `AutoDriver`, author `104madlife`, version `0.1`.

## Development Environment

- Game version: Next-Gen `4.0.0.103190(Build Machine)` observed for both DX11 and DX12 executables on 2026-09-02.
- Language: WitcherScript.
- Loader/integration: `modBootstrap-registry` calls `createAutoDriver()`.
- Standalone repository location: `D:\workspace\ModDev\Witcher3AutoDriver` on the migration host.
- Legacy repository location: `<game>/mods/AutoDriver`.
- Runtime discovery path before first standalone deployment: `<game>/mods/modAutoDriver`, a directory junction targeting the legacy repository.
- Vanilla script reference: `<game>/content/content0/scripts`.
- External runtime dependency: Bootstrap scripts, registry integration, and the matching `dlcBootstrap` resources. The current AutoDriver source no longer references StoryBoardUI, RadishSeeds, or SharedImports.
- No standalone WitcherScript compiler is currently available. Repository validation, packaging, and deployment regression tests are provided, but game launch remains the authoritative compile gate.

## Repository Layout

```text
AutoDriver/
├── content/scripts/local/mod_autodriver.ws
├── baselines/legacy-current/
├── modAutoDriver.input.settings
├── validate-project.ps1
├── package.ps1
├── deploy.ps1
├── restore-deployment.ps1
├── tests/test-deployment.ps1
├── GOD_TELEPORT_DEVELOPMENT_PLAN.md
├── README.md
├── PROJECT.md
└── docs/
    ├── interface-matrix.md
    ├── experiments.md
    ├── feature-dependency-audit.md
    └── pitfalls.md
```

The established Witcher 3 source and input layout is authoritative. Do not move it into a generic `src/`, `scripts/`, or `dist/` hierarchy.

## Runtime Integration

AutoDriver relies on integration outside this repository:

1. `<game>/mods/modAutoDriver` must contain the packaged runtime source. Before the first standalone deployment it is a junction to the legacy repository; afterward it becomes a real runtime-only directory.
2. `<game>/mods/modBootstrap-registry/content/scripts/local/mods_registry.ws` must register `add(createAutoDriver());`.
3. Input actions may need to be merged into `<documents>/The Witcher 3/input.settings`; preserve a backup before editing the live user file.

These external files are not owned by this Git repository. Verify them before concluding that a source change failed.

## Working Procedures

### Validate / compile

- Run `validate-project.ps1` for read-only repository and external-integration checks.
- There is no repository-local WitcherScript compiler.
- Launching the installed game/mod stack triggers WitcherScript compilation in the current setup.
- For every compiler failure, record the exact error, declaring type, receiver/inheritance context, attempted fix, and final result in `docs/experiments.md`.

### Package / deploy

- Run `package.ps1` to produce a runtime-only package without touching the game.
- Run `deploy.ps1 -GameRoot <path> -DryRun` before any real deployment.
- Run `tests/test-deployment.ps1` after changing packaging, deployment, or rollback behavior.
- The first real standalone deployment replaces only the verified `modAutoDriver` junction entry with a real runtime-only directory; it never mutates the junction target.
- Verify Bootstrap registration and user input rather than overwriting their shared files.
- Do not commit machine-specific absolute paths when `<game>` and `<documents>` placeholders are sufficient.

### Input configuration

- `modAutoDriver.input.settings` is the single canonical input template and declares all current `AutoDriver_*` actions.
- This installation previously required merging those bindings into the live user `input.settings`.
- The canonical template includes NumPad2 in both horse contexts and NumPad8/9 in the supported combat, swimming, diving, boat, climbing, and scripted-action contexts.

### Launch / reload

- Start the game after script or input changes and inspect compile output before testing hotkeys.
- Confirm the startup HUD message before diagnosing individual features.
- Test one feature and one primary question at a time; avoid combining unrelated runtime probes.

### Logs and observability

- `CModAutoDriver` uses Mod logging at `MLOG_DEBUG` and emits HUD messages for load, transitions, failures, and important results.
- The exact filesystem location of the Mod log is not recorded. Capture it during the next game run.
- Avoid per-frame logging; keep transition, retry, failure, target, and verification records.

### Cleanup / rollback

- Stop AutoDriver-owned state before testing another movement mode.
- The code should remove only equipment modifiers marked with `AutoDriverIndestructible`.
- Restore the backed-up live input file if input merging must be rolled back.
- Use `restore-deployment.ps1` with the exact receipt for runtime rollback. The first rollback can recreate the recorded legacy junction.
- Bootstrap and user-input files are verify-only external state and are never changed by core deployment or rollback.

## Current Input Semantics

| Key | Action | Current purpose |
| --- | --- | --- |
| NumPad2 | `AutoDriver_HorseWander` | Mounted horse wander prototype |
| NumPad3 | `AutoDriver_WalkWander` | Official-style player walk wander |
| NumPad6 | `AutoDriver_ToggleHorse` | Summon/mount or dismount the player horse |
| NumPad7 | `AutoDriver_GodMode` | Health invulnerability and marked equipment protection |
| NumPad8 | `AutoDriver_OfficialTeleport` | Sequential official fast-travel traversal |
| NumPad9 | `AutoDriver_RandomXYTeleport` | Validated random XY near a current-world road-sign anchor |

Input availability varies by player state. Use `modAutoDriver.input.settings` as the only repository source for input coverage.

## Current Validation Boundary

Confirmed historical observations include successful Mod bootstrap/HUD startup, live input activation, player movement through `ActionMoveTo(...)`, and failure of direct moving-agent control on the player. The NumPad4/5 clone and camera experiments were removed on 2026-10-05 after being judged unsuccessful.

The latest implementation still needs revalidation for:

- compilation after the latent verified local-teleport changes;
- compilation after removal of NumPad4/5 and the StoryBoardUI resource references;
- direct local teleport from combat, swimming, diving, boat, passenger, climbing, and scripted-action states;
- cross-world teleport from those states;
- horse toggle and mounted teleport preparation;
- god-mode damage, equipment, and underwater behavior;
- official teleport cursor persistence and Harbor destinations;
- random-XY behavior across major worlds and terrain categories.

Do not promote these items to `Confirmed` merely because code exists. Update `docs/interface-matrix.md` only after collecting matching compile/runtime evidence.

## Current Conventions

- Preserve the established Witcher 3 Mod layout and external loader conventions.
- Verify API ownership, receiver type, inheritance, parameters, return type, and latent behavior before copying an engine call.
- Use `Confirmed`, `Probable`, `Hypothesis`, `Known-bad`, and `Stale / needs revalidation` consistently.
- Record reusable interfaces in `docs/interface-matrix.md`.
- Record raw research and observations in `docs/experiments.md`.
- Record repeatable, scoped traps in `docs/pitfalls.md`.
- Treat older experiment entries as historical evidence, not necessarily the current implementation.

## Reference Material

- `docs/interface-matrix.md`: capability-oriented interface and evidence cache.
- `docs/experiments.md`: chronological research, compile tests, runtime observations, and failures.
- `docs/pitfalls.md`: verified mistakes and avoidance rules.
- `GOD_TELEPORT_DEVELOPMENT_PLAN.md`: design record for NumPad7/8/9 work.
- `AGENT.md`: legacy focused notes retained for compatibility; durable lessons are also represented in `docs/pitfalls.md`.
- Historical StoryBoardUI experiments remain recorded in `docs/experiments.md`; StoryBoardUI is not a current AutoDriver dependency.
- Vanilla game scripts: authoritative declarations for player, movement, vehicle, navigation, camera, inventory, and fast-travel interfaces.

# The Witcher 3 AutoDriver Standalone Repository Migration Plan

Status: repository conversion, first real deployment, feature/dependency cleanup, and post-cleanup game validation complete

Plan date: 2026-09-02

> Scope change: NumPad4/5 and their StoryBoardUI resource dependencies were removed on 2026-10-05, and the shared registry no longer calls `createStoryboardUi()`. Historical baseline hashes below describe the pre-cleanup source. Current validation, packaging, deployment, and acceptance use the reduced feature set and the canonical `modAutoDriver.input.settings`; see `feature-dependency-audit.md`.

> Packaging update: Bootstrap 0.5 Next-Gen is now vendored under `external/Bootstrap` for private portable installation. The historical migration phases below intentionally describe the earlier AutoDriver-only package and verify-only integration boundary.

Legacy repository:

```text
E:\SteamLibrary\steamapps\common\The Witcher 3\mods\AutoDriver
```

Proposed standalone repository:

```text
D:\workspace\ModDev\Witcher3AutoDriver
```

Target game installation:

```text
E:\SteamLibrary\steamapps\common\The Witcher 3
```

## 1. Objective

Move AutoDriver development out of the live Witcher 3 installation while preserving:

- the complete Git history and existing project knowledge;
- the established WitcherScript `content/scripts/local` layout;
- current source and input files byte-for-byte for the first migrated build;
- the Bootstrap registration and user input integration already present on this machine;
- a reversible route back to the current `modAutoDriver` junction;
- clear evidence boundaries between repository validation, game compilation and runtime behavior.

The migration is a repository and deployment-boundary change. It is not a gameplay refactor and must not silently change AutoDriver behavior.

## 2. Current Confirmed Baseline

Observed on 2026-09-02:

| Item | Current evidence |
| --- | --- |
| Repository branch | `codex/standardize-mod-repo` |
| Standardized source HEAD before the plan commit | `1829e75327fb332010a53d9d3636db3e94b984ba` |
| History-preserving migration baseline | `fd0476376bfd455891dabaed9f7b5563d4d4fbf4` |
| Working tree | Clean |
| Legacy branch | `master` at `cb69c46` |
| Git remote | None |
| Game executable version | `4.0.0.103190(Build Machine)` for DX11 and DX12 |
| Runtime discovery path | `<game>\mods\modAutoDriver` |
| Discovery path type | Directory junction |
| Junction target | `<game>\mods\AutoDriver` |
| Bootstrap registration | `add(createAutoDriver());` present in `mods_registry.ws` |
| StoryBoardUI | `modStoryboardUi` installed |
| User input integration | AutoDriver actions present in `<documents>\The Witcher 3\input.settings` |
| Standalone compiler | Not found in the inspected environment |

Baseline SHA-256 values:

| File | SHA-256 |
| --- | --- |
| `content/scripts/local/mod_autodriver.ws` | `D33F43EA882480D60D2579E14133BE47F6ADA6BFC854AD2DA2750BD59318C93D` |
| `AutoDriver.input.settings` | `1A23B186A5C884B6EC227C42F49D0E0C04DF376F155BAFCC8FB20F5A0F386E11` |
| `modAutoDriver.input.settings` | `4A4859952FEFBD9523AA96D0250F068D603CF163F84F2B6E5143FFC74D74B9E8` |
| Bootstrap `mods_registry.ws` | `DF90101B1E4ABC7482F4D03C693153A2A85281CF4478E623352C9929812EF589` |
| Live user `input.settings` | `66F3F786CA26D0B49CDE75D7242E5C95D0C03CB51814B61435CE589E3C2A3B79` |

The Bootstrap and user-input hashes describe external installation state. They are evidence, not files to import into Git.

## 3. Evidence Boundary

### Confirmed

- The repository is dedicated to AutoDriver and has a clean, useful Git history.
- The project knowledge structure has already been standardized.
- The game discovers AutoDriver through a `modAutoDriver` junction and Bootstrap registration.
- Historical runtime evidence exists for Mod startup, input reception, player movement and the StoryBoardUI static-camera route.
- Direct movement-agent control of the real player is a known-bad route in the recorded context.
- Direct `AddTimer`/`RemoveTimer` calls on `CModAutoDriver` are a known-bad API-ownership route.

### Probable or pending

- The current source is likely close to compilable because it contains the prior compile corrections, but no current-game compile log was found during migration planning.
- The latest 2026-07-14 expanded-state teleport implementation still needs current-game compilation and runtime acceptance.
- Horse toggle, mounted teleport preparation, god-mode durability/oxygen behavior, official teleport traversal and broad random-XY coverage remain runtime-pending as recorded in project knowledge.

Repository migration must not promote these runtime-pending capabilities to `Confirmed`.

## 4. Scope

### In scope

- Preserve the complete existing Git object database, branches and commit history.
- Create `D:\workspace\ModDev\Witcher3AutoDriver` as the development repository.
- Establish `main` at the current standardized commit while retaining historical branch pointers.
- Preserve the migration baseline byte-for-byte, then make later feature cleanup auditable in normal Git commits.
- Add README, migration receipts, local configuration example, validation, packaging, deployment and rollback workflows.
- Package only AutoDriver-owned runtime content.
- Detect and safely migrate the current `modAutoDriver` junction to a real deployed directory.
- Validate external Bootstrap and user-input state without taking ownership of them.
- Test deployment and rollback in sandboxes before touching the real game installation.
- Run a real-root Dry Run with zero writes.
- Leave a user-executed in-game acceptance checklist.

### Out of scope for the first migration

- Refactoring `mod_autodriver.ws`.
- Fixing or redesigning the retained movement, horse, god-mode or teleport behavior.
- Vendoring `modBootstrap`, `modBootstrap-registry` or vanilla scripts.
- Automatically overwriting the shared Bootstrap registry.
- Automatically rewriting the live user `input.settings`.
- Installing a third-party WitcherScript compiler or Mod toolchain.
- Claiming game compilation or gameplay success without a matching game run.

## 5. Ownership Model

### Repository-owned source and metadata

```text
content\scripts\local\mod_autodriver.ws
modAutoDriver.input.settings
PROJECT.md
README.md
docs\
baselines\
validate-project.ps1
package.ps1
deploy.ps1
restore-deployment.ps1
.mod-project.local.ps1.example
```

### Deployment-owned runtime path

```text
<game>\mods\modAutoDriver\content\scripts\local\mod_autodriver.ws
```

Only files listed in a generated package manifest are deployment-owned. Deployment must not copy `.git`, project documentation, baselines or development scripts into the game.

### External, verify-only state

```text
<game>\mods\modBootstrap
<game>\mods\modBootstrap-registry
<game>\mods\modBootstrap-registry\content\scripts\local\mods_registry.ws
<documents>\The Witcher 3\input.settings
<game>\content\content0\scripts
```

Core deployment must never overwrite or delete these external paths.

## 6. Target Repository Layout

```text
Witcher3AutoDriver/
├── content/
│   └── scripts/local/mod_autodriver.ws
├── baselines/
│   └── legacy-current/
│       ├── manifest.json
│       └── integration-state.json
├── docs/
│   ├── standalone-migration-plan.md
│   ├── interface-matrix.md
│   ├── experiments.md
│   ├── pitfalls.md
│   └── legacy/
├── modAutoDriver.input.settings
├── validate-project.ps1
├── package.ps1
├── deploy.ps1
├── restore-deployment.ps1
├── .mod-project.local.ps1.example
├── .gitignore
├── PROJECT.md
└── README.md
```

The existing Witcher 3 layout remains authoritative. Do not move the source into a generic `src/` directory.

Generated packages, receipts and sandbox directories must be Git-ignored.

## 7. Input-File Policy

`modAutoDriver.input.settings` is the single canonical repository template. It contains every registered action, the expanded NumPad8/9 state coverage formerly present only in `AutoDriver.input.settings`, and NumPad2 in both horse contexts. The obsolete duplicate template was deleted after its historical hash was recorded in the migration baseline.

Core runtime deployment verifies the live `input.settings` but does not overwrite it. User-profile changes remain a separately backed-up integration operation.

## 8. External Dependency Policy

### Required to instantiate the Mod

- `modBootstrap` must be installed.
- `modBootstrap-registry` must compile with `add(createAutoDriver());` present exactly once in the effective registry.

### Removed feature dependency

The retired NumPad4/5 camera and Geralt-clone experiments formerly loaded StoryBoardUI resources. Those features and resource references have been removed. StoryBoardUI, RadishSeeds, and SharedImports are not current AutoDriver dependencies.

### User profile integration

The live `input.settings` is user-owned shared state. Validation must report:

- presence of every `AutoDriver_*` action;
- contexts in which each action appears;
- duplicate bindings;
- differences from the canonical repository input template.

Core deployment does not mutate the live file.

## 9. Phase 0 — Preflight and Freeze

Before any write:

1. Verify that The Witcher 3 and its launcher are not running.
2. Verify the exact source and destination paths.
3. Refuse to continue if the destination repository already exists.
4. Confirm the legacy repository worktree is clean.
5. Record all local branches, tags, HEAD and remotes.
6. Run `git fsck --full` on the legacy repository.
7. Hash every tracked file and write a temporary preflight receipt outside the game directory.
8. Inspect `modAutoDriver` with reparse-point-aware commands; do not recurse through it during ownership discovery.
9. Record its link type and exact target.
10. Hash the Bootstrap registry and live user input file.
11. Record installed game executable versions and the presence of external dependencies.

Exit condition: the legacy Git repository is healthy, the destination is absent, and every external integration point has a recorded identity.

## 10. Phase 1 — History-Preserving Repository Relocation

The current repository is already dedicated and clean, so migration must preserve history rather than create an unrelated repository.

1. Copy the repository, including `.git`, to the new destination using an exact filesystem operation.
2. Do not move or delete the legacy repository.
3. In the new copy, verify:
   - the same HEAD commit;
   - the same branches and tags;
   - a clean worktree;
   - `git fsck --full` success;
   - identical hashes for all tracked files.
4. Create `main` at the clean history-preserving migration baseline `fd0476376bfd455891dabaed9f7b5563d4d4fbf4`, whose parent history contains the standardized source commit.
5. Retain `master` and `codex/standardize-mod-repo` as historical pointers until migration and in-game acceptance are complete.
6. Confirm the new repository has no accidental local-path remote.

Exit condition: the new repository is a complete, independent and hash-equivalent copy of the legacy repository.

## 11. Phase 2 — Raw Baseline and Documentation

Create a first migration commit containing only migration evidence and documentation:

- `baselines/legacy-current/manifest.json` with tracked-file hashes and source commit;
- `baselines/legacy-current/integration-state.json` with game version, junction identity and external integration hashes;
- `README.md` with project purpose, dependency model and safe commands;
- this migration plan under `docs/`;
- any required clarification to `PROJECT.md`, without rewriting historical evidence.

Do not modify the WitcherScript or either input file in this commit.

Suggested commit message:

```text
Record Witcher 3 AutoDriver standalone migration baseline
```

## 12. Phase 3 — Repository Validation

Implement `validate-project.ps1` as a read-only validator. It must:

1. Verify required repository files and relative paths.
2. Verify the source hash when running in baseline-preservation mode.
3. Confirm one `createAutoDriver()` factory and the expected `CModAutoDriver` definition.
4. Enumerate `theInput.RegisterListener` action names.
5. Compare registered actions with the canonical repository input file.
6. Reject unexpected input actions and require NumPad2 in both horse contexts.
7. Reject current StoryBoardUI resource references.
8. When `-GameRoot` is supplied, verify:
   - DX11/DX12 game executable versions;
   - Bootstrap and Bootstrap registry presence;
   - exactly one effective `add(createAutoDriver());` line;
   - the type and target of any existing `modAutoDriver` path.
9. When `-UserInputPath` is supplied, summarize live action coverage and duplicates.
10. Emit an ignored JSON validation receipt.

This validator cannot claim that WitcherScript compiles. Its result must be named `repository validation`, not `build success`.

Suggested commit message:

```text
Add Witcher 3 AutoDriver repository validation
```

## 13. Phase 4 — Reproducible Packaging

Implement `package.ps1` with no deployment side effects.

Expected output:

```text
artifacts\Release\modAutoDriver\content\scripts\local\mod_autodriver.ws
artifacts\Release\package-manifest.json
```

Requirements:

- package only explicitly declared runtime-owned files;
- preserve relative paths and file bytes;
- reject a dirty source tree by default, with an explicit override only for development;
- record source commit, source dirty state, file sizes and SHA-256 values;
- call repository validation before packaging;
- never copy into the game directory;
- never include `.git`, documentation, input templates, external dependencies or local configuration.

Suggested commit message:

```text
Add reproducible AutoDriver runtime packaging
```

## 14. Phase 5 — Transactional Deployment

Implement `deploy.ps1` with explicit `-GameRoot` and `-DryRun` support.

### General safety requirements

- Refuse real deployment while the game or launcher is running.
- Resolve and validate the absolute game root.
- Verify the package manifest and every source hash.
- Verify required Bootstrap registration before mutation.
- Never modify Bootstrap, third-party Mods, vanilla scripts or user settings.
- Write a deployment receipt containing previous state, new state and hashes.
- On any failure after mutation begins, perform bounded rollback.

### Existing junction migration

The current live destination is a junction. The deployment implementation must not copy through it.

Before replacing it:

1. Verify that `<game>\mods\modAutoDriver` is a junction.
2. Verify its target is exactly the recorded legacy repository.
3. Record the junction target and attributes in the receipt.
4. Stage the complete package in a separate non-junction directory.
5. Verify staged hashes.
6. Remove only the verified junction entry, never recursively delete or clean its target.
7. Create a real `<game>\mods\modAutoDriver` directory.
8. Copy the staged owned payload.
9. Verify deployed hashes and path type.
10. Confirm the legacy repository remains present and unchanged.

If the destination is a real directory rather than the expected junction, deployment must switch to the normal backup path or stop for review; it must not assume ownership.

### Dry Run contract

Dry Run must report:

- resolved source package and game root;
- destination path type;
- junction target, if present;
- exact files to deploy;
- external dependency status;
- proposed backup and receipt paths;
- rollback strategy.

Dry Run must produce zero filesystem writes, including no directory creation, backup or receipt.

Suggested commit message:

```text
Add transactional Witcher 3 AutoDriver deployment
```

## 15. Phase 6 — Receipt-Driven Rollback

Implement `restore-deployment.ps1`.

For the first junction-to-directory deployment, rollback must:

1. Require the exact deployment receipt.
2. Refuse while the game or launcher is running.
3. Verify that every currently deployed owned file still has the deployed hash.
4. Stop rather than overwrite ambiguous post-deployment changes.
5. Remove only the receipt-owned deployed files and empty directories.
6. Recreate the prior directory junction with the exact recorded target.
7. Verify the recreated junction type and target.
8. Verify that the legacy source repository hash remains unchanged.
9. Write a rollback receipt outside the restored junction.

For later real-directory deployments, rollback must restore the prior owned files from timestamped backups instead of recreating a junction.

Rollback must not touch Bootstrap, third-party Mods, vanilla scripts or user input configuration.

## 16. Phase 7 — Sandbox Verification

Before any real deployment, construct sandboxes covering these cases:

### Existing junction case

- a test junction points to a mock legacy repository;
- Dry Run reports the junction and makes zero changes;
- real deployment replaces only the link entry with a real runtime directory;
- the link target remains unchanged;
- rollback removes the deployed directory and recreates the exact junction.

### Existing real-directory case

- prior runtime files are backed up;
- new files deploy with matching hashes;
- rollback restores every prior hash.

### Clean install case

- no destination exists;
- deployment creates only the owned runtime tree;
- rollback removes only files introduced by that receipt.

### Negative cases

- missing or malformed package receipt;
- changed package hash;
- missing Bootstrap registration;
- unexpected junction target;
- destination changed after deployment;
- game process running;
- malformed or out-of-root receipt destination.

All negative cases must fail before mutation where possible.

## 17. Phase 8 — Real-Root Dry Run

Against the real game installation:

1. Fingerprint the current junction, its target, Bootstrap registry and user input file.
2. Run deployment Dry Run.
3. Recompute the same fingerprints.
4. Require byte-identical external files and unchanged link metadata.
5. Record the result in `docs/experiments.md`.

No real deployment occurs during repository conversion unless the user explicitly asks for it after reviewing the Dry Run.

## 18. Phase 9 — Real Deployment and Game Compilation

After Dry Run review:

1. Exit the game and launcher.
2. Run real deployment.
3. Verify the deployment receipt and final hashes.
4. Start the game using one renderer at a time, beginning with the user's normal renderer.
5. Capture the full WitcherScript compile result.
6. Confirm the AutoDriver startup HUD message.
7. If compilation fails, stop gameplay testing, preserve the exact error and roll back if required.

Game compilation is the first authoritative compile gate because no standalone compiler is currently available.

## 19. In-Game Acceptance Checklist

Test one primary behavior at a time and preserve exact observations.

### Core loading and cleanup

- [ ] WitcherScript compilation completes.
- [ ] AutoDriver startup HUD message appears once.
- [ ] No duplicate Mod instance or duplicate input callback is observed.
- [ ] Stopping each mode cleans up AutoDriver-owned state.

### Movement

- [ ] NumPad2 horse wander starts, retargets and stops.
- [ ] NumPad3 player walk wander starts, recovers from a stuck target and stops.

### Horse and protection

- [ ] NumPad6 summons/mounts a nearby horse without relocating to a remote horse.
- [ ] NumPad6 dismounts only an actual mounted horse.
- [ ] NumPad7 prevents health damage and applies only the marked equipment modifier.
- [ ] Disabling NumPad7 removes only AutoDriver-owned protection.

### Teleport

- [ ] NumPad8 local official teleport advances the persisted cursor correctly.
- [ ] NumPad8 cross-world teleport works or records the exact failure path.
- [ ] NumPad9 resolves a road-sign anchor and validates the final destination.
- [ ] Failed random-position resolution leaves the player at the safe anchor.
- [ ] Teleport preparation behaves correctly while mounted.

### Expanded input states

- [ ] Combat.
- [ ] Ciri combat.
- [ ] Swimming.
- [ ] Diving.
- [ ] Boat driver.
- [ ] Boat passenger.
- [ ] Jump/climb.
- [ ] Scripted action, where safe to test.

These expanded states are the highest-risk acceptance area and must remain `runtime pending` until tested.

## 20. Failure Classification

Classify failures before changing code:

| Failure layer | Evidence |
| --- | --- |
| Repository validation | Missing paths, action mismatch, malformed source/package manifest |
| Packaging | Wrong staged path or hash |
| Deployment | Junction/backup/copy/receipt failure |
| External integration | Missing Bootstrap registration or input action |
| Game compilation | Exact WitcherScript compiler error |
| Mod initialization | Compile succeeds but startup HUD is absent |
| Input delivery | Mod loads but a registered action is not received in a specific context |
| Gameplay behavior | Callback occurs but the state machine or game API behavior fails |

Do not change gameplay code to solve an installation or input-layer failure.

## 21. Rollback Policy

Two rollback boundaries must remain available:

### Repository rollback

- The legacy repository stays untouched at its original path.
- The new repository retains the original branch pointers and complete history.
- Migration commits are separated so tooling/documentation can be reverted without rewriting gameplay history.

### Runtime rollback

- Before first real deployment, the receipt records the exact junction target.
- Rollback restores that junction rather than copying historical source back into the game.
- Later deployments restore only receipt-owned runtime files.
- Shared integration files are never included in core runtime rollback because core deployment does not modify them.

## 22. Planned Commit Boundaries

Use small, auditable commits:

1. `Record Witcher 3 AutoDriver standalone migration baseline`
2. `Add Witcher 3 AutoDriver repository validation`
3. `Add reproducible AutoDriver runtime packaging`
4. `Add transactional Witcher 3 AutoDriver deployment`
5. `Record standalone migration verification`

Do not combine gameplay edits with these commits.

## 23. Definition of Done

Repository conversion is complete only when:

- [x] The legacy Git repository passes integrity checks and remains unchanged after the requested plan commit.
- [x] The standalone repository exists at the proposed destination with complete history.
- [x] `main` contains the standardized source baseline and historical branches remain available.
- [x] All raw source and input hashes match the legacy repository.
- [x] Baseline and external-integration receipts are recorded.
- [x] Repository validation passes without claiming game compilation.
- [x] Packaging produces only declared runtime-owned content.
- [x] Package output is hash-verified and Git-ignored.
- [x] Junction, real-directory and clean-install sandbox deployments pass.
- [x] Sandbox rollback restores the exact previous state in every case.
- [x] Negative paths reject unsafe or ambiguous operations.
- [x] Real-game-root Dry Run succeeds with zero writes.
- [x] Bootstrap, third-party Mods, vanilla scripts and user settings remain unmodified.
- [x] The new repository working tree is clean with separated migration commits.
- [x] The user receives exact deploy, rollback and in-game acceptance instructions.

Successful repository conversion does not imply successful gameplay. Runtime capabilities are promoted only after the user completes the in-game checklist and supplies the resulting compile/runtime evidence.

## 24. Execution Stop Conditions

Stop and request review if any of the following occurs:

- the legacy repository becomes dirty before its baseline is captured;
- the destination repository already exists;
- Git integrity or tracked-file hash comparison fails;
- `modAutoDriver` is not the expected junction or targets an unexpected path;
- Bootstrap registration is missing, duplicated or structurally ambiguous;
- deployment would need to overwrite a non-owned real directory without a verified backup;
- a receipt references a path outside the exact game root or standalone repository;
- the game or launcher is running during a mutating deployment/rollback;
- live user input must be changed to proceed;
- migration exposes a gameplay decision that would change existing behavior.

Ordinary documentation, packaging or script implementation errors are bounded migration work and should be corrected without changing the approved ownership model.

## 25. Execution Record — 2026-09-02

- Legacy plan commit and migration baseline: `fd0476376bfd455891dabaed9f7b5563d4d4fbf4`.
- Standalone baseline commit: `58d583ac9ea906f94f06d7ab437bfe0ccc1448a2`.
- Repository validation commit: `1e5839e`.
- Runtime packaging commit: `25b66e8`.
- Transactional deployment/rollback commit: `be6972d`.
- Deployment regression coverage commit: `d4df331`.
- Preserved source/package SHA-256: `D33F43EA882480D60D2579E14133BE47F6ADA6BFC854AD2DA2750BD59318C93D`.
- Repository validation: 57 checks passed, zero errors, zero warnings.
- Sandbox coverage: junction, existing directory, clean install, both Dry Runs, receipt rollback, and seven negative/ambiguous-state groups passed.
- Real-root Dry Run: passed with identical before/after protected fingerprints and no writes.
- Real deployment: intentionally not performed during repository conversion.
- Remaining boundary: user-approved real deployment, game WitcherScript compilation, and Section 19 runtime acceptance.

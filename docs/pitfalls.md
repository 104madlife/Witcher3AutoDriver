# Pitfalls

These entries record repeatable, evidence-backed traps. Their scope is AutoDriver's recorded Witcher 3 environment unless stated otherwise.

## Loader does not discover a non-`mod*` repository directory

- Game/runtime/language: The Witcher 3 Mod script discovery.
- Applicable versions: exact game/loader versions not recorded.
- Symptom: `modBootstrap-registry` reports that it cannot find `createAutoDriver()` even though the function exists in the repository source.
- Root cause: the repository directory `AutoDriver` was not loader-visible under the expected Mod naming convention.
- Verified fix/avoidance: expose the repository through `<game>/mods/modAutoDriver`; this installation uses a directory junction.
- Misleading workaround: editing the Bootstrap call or function name without first verifying script discovery.
- Evidence: successful startup HUD after the junction was introduced; 2026-06-01 experiment.
- Last verified: 2026-06-01.

## Mod-local input settings do not necessarily update the live profile

- Game/runtime/language: The Witcher 3 input configuration in this installed profile.
- Applicable versions: exact version not recorded.
- Symptom: the Mod initializes and displays its HUD message, but NumPad actions produce no response.
- Root cause: the live `<documents>/The Witcher 3/input.settings` did not contain the `AutoDriver_*` bindings.
- Verified fix/avoidance: back up the live file and merge the required actions into the applicable state sections.
- Misleading workaround: changing handler code before verifying that the action reaches the Mod.
- Evidence: 2026-06-01 input merge and subsequent binding diagnosis.
- Last verified: 2026-06-01.

## Duplicate repository input templates can drift

- Game/runtime/language: repository packaging and Witcher 3 input contexts.
- Applicable versions: repository before the 2026-10-05 input consolidation.
- Symptom: an action works in exploration but is absent from combat, swimming, boat, climbing, or another intended state.
- Root cause: `AutoDriver.input.settings` and `modAutoDriver.input.settings` were maintained independently and accumulated different state coverage.
- Verified fix/avoidance: keep only `modAutoDriver.input.settings` as the canonical template; validate every registered action against it and the live profile.
- Misleading workaround: keep both files and rely on maintainers to update them together.
- Evidence: repository comparison on 2026-08-15 and consolidation on 2026-10-05.
- Last verified: static source review 2026-10-05; revised template needs a fresh game run.

## Latent calls cannot appear directly in a return or condition

- Game/runtime/language: WitcherScript latent functions.
- Applicable versions: current base scripts used by this project; exact game version not recorded.
- Symptom: compiler error such as `latent calls not allowed in return statement`.
- Root cause: a latent call such as `ActionMoveTo(...)` was evaluated directly in `return` or control-flow syntax.
- Verified fix/avoidance: assign the latent result to a local variable first, then return or branch on that value.
- Misleading workaround: changing the function's declared return type without addressing latent evaluation rules.
- Evidence: `moveActorRandom` compile failure and fix on 2026-06-01.
- Last verified: 2026-06-01.

## Bare early return in a state event can produce a misleading conversion error

- Game/runtime/language: WitcherScript state/event compilation.
- Applicable versions: current base scripts used by this project; exact game version not recorded.
- Symptom: `Unable to convert from 'void' to 'Bool'` points near an `event OnEnterState(...)` branch.
- Root cause: a bare `return;` inside the state event was rejected with a misleading conversion diagnostic.
- Verified fix/avoidance: structure the event as conditional state transition versus work-loop entry; keep early returns only in contexts already proven to compile.
- Misleading workaround: searching only for an explicit Bool assignment at the reported line.
- Evidence: 2026-06-02 compile investigation.
- Last verified: 2026-06-02.

## `AddTimer` and `RemoveTimer` are not global `CMod` methods

- Game/runtime/language: WitcherScript engine API ownership.
- Applicable versions: engine declarations inspected on 2026-07-13; exact game version not recorded.
- Symptom: `Could not find function` when `CModAutoDriver` calls an unqualified timer method.
- Root cause: the methods are imported by `CEntity`; `CModAutoDriver extends CMod extends IScriptable` and does not inherit them.
- Verified fix/avoidance: use an independently verified scheduler or a real `CEntity` helper whose callback is declared on that timer owner.
- Misleading workaround: call `thePlayer.AddTimer(...)` while leaving the callback on `CModAutoDriver`; callbacks resolve on the owner entity.
- Evidence: engine `entity.ws`, StoryBoardUI inheritance comparison, and 2026-07-13 compile correction.
- Last verified: 2026-07-13.

## Shared rider status is not proof of a mounted horse

- Game/runtime/language: Witcher 3 player/vehicle state.
- Applicable versions: current base scripts used by this project; exact game version not recorded.
- Symptom: horse-only dismount or teleport preparation is applied while swimming, sailing, or using another vehicle state.
- Root cause: `CAIStorageRiderData.sharedParams.mountStatus` represents shared vehicle state and does not identify the vehicle as a horse.
- Verified fix/avoidance: resolve a real horse through `GetHorseCurrentlyMounted()` or `GetUsedHorseComponent()` before applying horse behavior.
- Misleading workaround: gate every teleport on generic rider data availability.
- Evidence: 2026-07-14 expanded-state correction and base-script inspection.
- Last verified: 2026-07-14.

## Immediate mounting of a remote persistent horse can relocate the player

- Game/runtime/language: Witcher 3 horse mounting.
- Applicable versions: current installed environment; exact game version not recorded.
- Symptom: pressing the horse toggle appears to teleport the player to an unexpected XY position.
- Root cause: `GetHorseWithInventory()` can return a valid persistent horse far outside the local area; `VMT_ImmediateUse` moves the player to that entity's mount slot.
- Verified fix/avoidance: allow immediate mount only for a living horse within a bounded distance; otherwise invoke the official recall flow and wait for a nearby horse.
- Misleading workaround: treating a non-null persistent horse handle as proof that immediate mounting is locally safe.
- Evidence: repeatable XY relocation diagnosis and correction on 2026-07-13.
- Last verified: 2026-07-13.

## Direct movement-agent writes do not control the real player reliably

- Game/runtime/language: Witcher 3 exploration locomotion.
- Applicable versions: installed environment tested on 2026-06-01.
- Symptom: repeated speed and direction writes do not move Geralt.
- Root cause: the native player locomotion controller overwrites or ignores the external moving-agent values.
- Verified fix/avoidance: prefer an official player action/decorator route and validate it as a bounded experiment.
- Misleading workaround: increasing the write frequency without first proving ownership of locomotion channels.
- Evidence: NumPad4 direct-wander runtime experiment.
- Last verified: 2026-06-01.

## `ActionCancelAll()` can exceed AutoDriver's intended ownership

- Game/runtime/language: Witcher 3 actor action system.
- Applicable versions: current repository behavior and base-script interfaces.
- Symptom: native movement, traversal, or another player action is cancelled while preparing an unrelated feature such as teleport.
- Root cause: `ActionCancelAll()` cancels actor actions broadly; it is not scoped to a single AutoDriver request.
- Verified fix/avoidance: use the Mod-only cleanup path for teleport preparation and reserve broad cancellation for an AutoDriver movement mode whose ownership is understood.
- Misleading workaround: calling it as a universal stuck-recovery or state-normalization step.
- Evidence: 2026-07-14 expanded-state teleport design and current source.
- Last verified: source review 2026-08-15; affected runtime states still need validation.

## Failed reference-Mod experiments can become accidental hard dependencies

- Game/runtime/language: Witcher 3 entity resource loading.
- Applicable versions: current repository and installed StoryBoardUI reference.
- Symptom: a core AutoDriver installation appears to require StoryBoardUI, RadishSeeds, or SharedImports even when the failed NumPad4/5 features are not used.
- Root cause: the former implementation loaded StoryBoardUI camera/clone resources, while the shared Bootstrap registry also called `createStoryboardUi()` unconditionally.
- Verified fix/avoidance: remove the failed feature code and resource loads, and keep the AutoDriver registry entry limited to `add(createAutoDriver());`.
- Misleading workaround: leave the unconditional factory call in the registry and describe StoryBoardUI as optional.
- Evidence: 2026-10-05 dependency audit and removal; current static scan contains no StoryBoardUI reference in AutoDriver source or registry.
- Last verified: static source review 2026-10-05; reduced installation still needs in-game compilation after the latest cleanup.

## Copying into a junction-backed runtime path can mutate the source repository

- Game/runtime/language: Windows deployment of a Witcher 3 Mod whose `modAutoDriver` discovery path is a directory junction.
- Applicable versions: legacy AutoDriver installation observed on 2026-09-02.
- Symptom: a deployment that appears to update the game-side Mod also changes files inside the legacy development repository.
- Root cause: ordinary file operations follow the junction and write to its target.
- Verified fix/avoidance: inspect the reparse-point type and exact target first; stage and verify the package elsewhere; remove only the verified junction entry; then create a real runtime directory and copy receipt-owned files.
- Misleading workaround: treating `<game>/mods/modAutoDriver` as an ordinary directory or recursively deleting it before resolving its target.
- Evidence: junction sandbox deployment and rollback regression test.
- Last verified: 2026-09-02.

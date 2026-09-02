# Interface Matrix

This file is a reusable capability cache. Every entry is scoped to the recorded environment and must be revalidated when the game, loader, reference Mod, or implementation route changes.

## Evidence States

- `Confirmed`: supported by authoritative declarations plus matching compile/runtime evidence.
- `Probable`: strong source or implementation evidence exists, but the exact current target context is not fully verified.
- `Hypothesis`: plausible and testable, but not yet verified.
- `Known-bad`: failed, dangerous, or incompatible in the recorded context.
- `Stale / needs revalidation`: earlier evidence may no longer match the current implementation or environment.

## Capability Index

| Capability | Interface or entry point | Evidence | Last verified |
| --- | --- | --- | --- |
| Discover and instantiate the Mod | `modAutoDriver` directory + `modBootstrap-registry` + `createAutoDriver()` | Confirmed | 2026-06-01 |
| Register and receive Mod input | `theInput.RegisterListener(...)` + live `input.settings` merge | Confirmed | 2026-06-01 |
| Move the player with actor actions | `ActionMoveTo(...)` / `ActionMoveToAsync(...)` | Confirmed, unstable | 2026-06-01 |
| Drive player movement-agent values directly | `SetGameplayRelativeMoveSpeed(...)` + direction | Known-bad | 2026-06-01 |
| Force official-style player movement | `CAIMoveToPoint` + `CAIPlayerActionDecorator` + `ForceAIBehavior(...)` | Probable | 2026-06-02 |
| Find a local navigable target | navigation safe-spot/Z tests + moving-agent validity | Probable | 2026-07-12 |
| Follow an NPC with a static camera | StoryBoardUI `interactive_camera.w2ent` + `CStaticCamera` | Confirmed, quality-limited | 2026-06-02 |
| Spawn and drive a Geralt-like clone | StoryBoardUI `geralt_npc.w2ent` + `CAIMoveToPoint` | Probable | 2026-06-02 |
| Identify and toggle the player horse | horse component/entity + riding-manager state | Probable | 2026-07-13 |
| Enumerate and issue official teleport | `GetFastTravelPoints(...)` + local/global routes | Probable | 2026-07-14 |
| Find validated random XY destinations | road-sign anchor + navigation/physics validation | Probable | 2026-07-12 |
| Protect health and equipment durability | immortality channel + owned inventory marker | Probable | 2026-07-13 |
| Run a repeating timer directly on `CModAutoDriver` | `AddTimer` / `RemoveTimer` | Known-bad | 2026-07-13 |

## Capability: Discover and instantiate the Mod

- Game/runtime: The Witcher 3, exact version not recorded; `modBootstrap-registry` installed.
- Entry point: global `createAutoDriver() : CMod`, registered through `add(createAutoDriver());`.
- Evidence state: Confirmed.
- Ownership/lifecycle: `CModAutoDriver extends CMod`; initialization registers listeners, enters idle state, and emits a HUD/log message.
- Known limitations: the repository name `AutoDriver` was not loader-visible in this setup. A `modAutoDriver` directory junction is used.
- Source: `content/scripts/local/mod_autodriver.ws`; runtime startup HUD observation in `experiments.md`.
- Last verified: 2026-06-01.

## Capability: Register and receive Mod input

- Game/runtime: The Witcher 3, installed user profile.
- Interface: `theInput.RegisterListener(this, handler, action)` plus action entries in Mod and live user input settings.
- Evidence state: Confirmed for this installation.
- Ownership/lifecycle: listeners are registered by `CModAutoDriver.init()`.
- Known limitations: Mod-local settings did not populate the existing live user file automatically. The two repository input files currently differ in state coverage.
- Source: source `init()`, both `*.input.settings` files, and 2026-06-01 input experiment.
- Last verified: 2026-06-01.

## Capability: Move the real player with actor movement actions

- Game/runtime: exploration state, exact game version not recorded.
- Interface: `CActor.ActionMoveTo(...)` and `ActionMoveToAsync(...)` on `thePlayer`.
- Evidence state: Confirmed but operationally unstable.
- Ownership/lifecycle: movement is owned by a temporary AutoDriver state; cancellation and retargeting affect player AI actions.
- Known limitations: the first route stopped after roughly 20 seconds and later remained prone to stuck states. `ActionCancelAll()` can interfere with non-Mod actions and must not be used as generic teleport preparation.
- Source: vanilla `actor.ws`; 2026-06-01 walk experiments.
- Last verified: 2026-06-01.

## Capability: Drive player movement-agent values directly

- Game/runtime: real player locomotion controller in exploration.
- Interface: `SetGameplayRelativeMoveSpeed(...)`, `SetGameplayMoveDirection(...)`, and `SetDirectionChangeRate(...)`.
- Evidence state: Known-bad for moving the real player from this Mod loop.
- Root observation: writing the values repeatedly did not move the player, consistent with the native player locomotion controller overwriting or ignoring them.
- Source: 2026-06-01 direct-wander experiment.
- Last verified: 2026-06-01.

## Capability: Force official-style player movement

- Game/runtime: WitcherScript player actions.
- Interface: create `CAIMoveToPoint`, optionally wrap it in `CAIPlayerActionDecorator`, then call `ForceAIBehavior(..., BTAP_Emergency)`.
- Evidence state: Probable; authoritative vanilla examples and repository implementation exist, but a matching successful runtime observation is not recorded.
- Ownership/lifecycle: the forced action must be stopped when leaving the AutoDriver movement state.
- Known limitations: player state and native input may still interrupt the action; repeated cancellation can have side effects.
- Source: vanilla `temp.ws`, `scenePlayer.ws`, `r4Player.ws`; 2026-06-02 experiment; current source.
- Last verified: implementation review 2026-08-15; runtime pending.

## Capability: Find a local navigable destination

- Game/runtime: current loaded world/navigation data.
- Interface: `NavigationFindSafeSpot(...)`, `NavigationComputeZ(...)`, optional `PhysicsCorrectZ(...)`, and moving-agent `IsPositionValid(...)`.
- Evidence state: Probable for the current combined pipeline.
- Ownership/lifecycle: queries require the relevant world area to be loaded; distant searches use a known fast-travel anchor and a streaming delay.
- Known limitations: a rectangular XY range is not proof of playable terrain. Physics Z correction alone is insufficient. No brute-force fallback is allowed after validation failure.
- Source: vanilla world/navigation declarations; 2026-06-01 target experiments; 2026-07-12 implementation.
- Last verified: source review 2026-08-15; broad runtime validation pending.

## Capability: Follow a moving NPC with a static camera

- Game/runtime: StoryBoardUI resources installed and mounted.
- Interface/resource: load `dlc/modtemplates/storyboardui/interactive_camera.w2ent`, create `CStaticCamera`, and update its transform.
- Evidence state: Confirmed, with quality limitations.
- Ownership/lifecycle: AutoDriver creates, activates, updates, and stops its camera when entering/leaving the camera state.
- Known limitations: runtime follow worked but jittered; smoothing was implemented afterward and needs matching validation. Direct use of the top game camera failed when the object was `CCustomCamera` rather than `CCamera`.
- Source: 2026-06-01/02 camera experiments; current source.
- Last verified: 2026-06-02.

## Capability: Spawn and drive a Geralt-like NPC clone

- Game/runtime: StoryBoardUI DLC resources installed and mounted.
- Interface/resource: `dlc/modtemplates/storyboardui/geralt_npc.w2ent`, `theGame.CreateEntity(...)`, `CAIMoveToPoint`, and `ForceAIBehavior(...)`.
- Evidence state: Probable.
- Ownership/lifecycle: the clone is tagged as `AutoDriverClone`, driven while the state is active, and destroyed on cleanup.
- Known limitations: the current route does not clone the player's equipment/appearance through StoryBoardUI's full clone path. Runtime success is not recorded.
- Source: StoryBoardUI `storyboardasset.ws`; 2026-06-02 experiment; current source.
- Last verified: implementation review 2026-08-15; runtime pending.

## Capability: Identify and toggle the player horse

- Game/runtime: Witcher 3 riding manager and persistent player horse.
- Interface: `GetHorseCurrentlyMounted()`, `GetUsedHorseComponent()`, persistent horse lookup, `MountVehicle(...)`, `DismountVehicle(...)`, and riding-manager task/status checks.
- Evidence state: Probable.
- Ownership/lifecycle: a dedicated latent state waits for mount/dismount completion and applies bounded timeouts.
- Known limitations: generic `CAIStorageRiderData.mountStatus` is shared vehicle state and cannot identify a horse. Immediate mounting of a remote persistent horse can relocate the player.
- Source: vanilla actor/player/vehicle scripts; 2026-07-13 implementation and correction.
- Last verified: source review 2026-08-15; runtime pending.

## Capability: Enumerate and issue official teleports

- Game/runtime: Witcher 3 map manager and world-change system.
- Interface: `GetFastTravelPoints(false, false, false, false, false)`, point-position resolution, `TeleportWithRotation(...)`, `ScheduleWorldChangeToPosition(...)`, and `ScheduleWorldChangeToMapPin(...)`.
- Evidence state: Probable.
- Ownership/lifecycle: a dedicated latent state performs horse preparation, issues one operation, verifies local arrival, and returns to idle. Sequential cursor state uses the `autodriver_official_teleport_index` game fact.
- Known limitations: local transforms can be overwritten by combat, traversal, boat, or scripted states; Harbor destinations and cross-world cursor persistence are not validated.
- Source: `GOD_TELEPORT_DEVELOPMENT_PLAN.md`, 2026-07-12/14 experiments, current source.
- Last verified: source review 2026-08-15; runtime pending.

## Capability: Protect health and equipment durability

- Game/runtime: player immortality and inventory systems.
- Interface: `SetImmortalityMode(...)`, `MA_Indestructible`, and the `AutoDriverIndestructible` item modifier marker.
- Evidence state: Probable.
- Ownership/lifecycle: enable adds only missing abilities and records ownership; disable removes only marked changes; initialization clears stale marked protections.
- Known limitations: existing durability is not repaired, newly acquired items are not protected until retoggle, and the intended repeating oxygen timer route was removed after a compile failure.
- Source: 2026-07-12/13 experiments and current source.
- Last verified: source review 2026-08-15; runtime pending.

## Capability: Run a repeating timer directly on the Mod class

- Game/runtime/language: WitcherScript; `CModAutoDriver extends CMod extends IScriptable`.
- Interface: unqualified `AddTimer(...)` / `RemoveTimer(...)` from the Mod class.
- Evidence state: Known-bad.
- Ownership/lifecycle: those methods belong to `CEntity`; timer callbacks resolve on the timer-owning entity.
- Known limitations: moving the call to `thePlayer` does not make a callback declared on `CModAutoDriver` run.
- Source: engine `entity.ws`; compile error investigation on 2026-07-13.
- Last verified: 2026-07-13.

## Capability: Validate and package the standalone repository

- Game/runtime: The Witcher 3 Next-Gen `4.0.0.103190(Build Machine)`; PowerShell repository tooling.
- Interface: `validate-project.ps1`, `package.ps1`, baseline manifests, and package manifest.
- Evidence state: Confirmed for repository structure and packaging; not a WitcherScript compile result.
- Ownership/lifecycle: validation reads source and optional external integration state; packaging writes only ignored `artifacts/<Configuration>` output.
- Known limitations: no standalone WitcherScript compiler was found, so game launch remains the authoritative compile gate.
- Source: standalone migration implementation and 57-check validation receipt.
- Last verified: 2026-09-02.

## Capability: Transactionally deploy a junction-backed WitcherScript Mod

- Game/runtime: Windows directory junction at `<game>/mods/modAutoDriver` and a runtime-only WitcherScript package.
- Interface: `deploy.ps1`, `restore-deployment.ps1`, package manifest, deployment receipt, and rollback receipt.
- Evidence state: Confirmed in junction, existing-directory, and clean-install sandboxes; real game root Dry Run confirmed with zero writes.
- Ownership/lifecycle: deployment owns only `modAutoDriver/content/scripts/local/mod_autodriver.ws`; Bootstrap, StoryBoardUI, vanilla scripts, user input, and the legacy junction target are verify-only.
- Known limitations: the first real deployment has not been executed; game compilation and gameplay remain pending. Rollback refuses a payload changed after deployment.
- Source: `tests/test-deployment.ps1` and the 2026-09-02 migration experiment.
- Last verified: 2026-09-02.

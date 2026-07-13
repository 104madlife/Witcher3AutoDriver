# AutoDriver Project Notes

## Project Overview

AutoDriver is a planned The Witcher 3 mod for automatically collecting in-game visual data by driving character movement and state changes.

Current project folder:

```text
E:\SteamLibrary\steamapps\common\The Witcher 3\mods\AutoDriver
```

This folder has been initialized as a local Git repository for future code management.

## Game And Mod Context

- Game: The Witcher 3
- Current workspace: the game's `mods` directory
- AutoDriver target location: `E:\SteamLibrary\steamapps\common\The Witcher 3\mods\AutoDriver`
- Reference mod: StoryBoardUI
- Reference mod path: `E:\SteamLibrary\steamapps\common\The Witcher 3\mods\modStoryboardUi`

The user currently has no prior Witcher 3 mod development experience, so this project should keep implementation notes, discovered interfaces, mod structure decisions, and useful references in this Markdown file as the work progresses.

## Required Features

1. Automatic character walking movement, also described as wander behavior.
2. Random character teleportation.
3. Automatic wander movement while the character is mounted on a horse.
4. Movement speed tier switching while walking or mounted, for example switching from slow walk to fast run.

## Optional Features

These may be harder to implement, but should be investigated and implemented if feasible:

1. Character model switching.
2. Random teleportation while mounted on a horse.
3. Automatic combat.

## Reference Material: StoryBoardUI

StoryBoardUI is the main reference object for later research, reverse engineering, and API discovery.

Initial observed structure:

```text
modStoryboardUi
+-- content
|   +-- blob0.bundle
|   +-- metadata.store
|   +-- scripts
|       +-- local
|           +-- settings
|           +-- shotviewer
|           +-- w2scenedescription
|           +-- workmodes
|           +-- mod_additional_animations.ws
|           +-- mod_additional_effects.ws
|           +-- mod_additional_templates.ws
|           +-- mod_additional_voicelines.ws
|           +-- mod_storyboardui.ws
|           +-- storyboard.ws
|           +-- storyboardshot.ws
+-- modStoryboardUi.input.settings
```

Potentially useful research areas inside StoryBoardUI:

- Input binding and hotkey handling, especially `modStoryboardUi.input.settings`.
- Script entry points in `content\scripts\local`.
- Any camera, actor, scene, teleport, animation, or world-control APIs used by `mod_storyboardui.ws`, `storyboard.ws`, and `storyboardshot.ws`.
- Any existing utilities for spawning, moving, animating, mounting, changing appearances, or controlling Geralt and other actors.

## Development Notes

- Prefer preserving Witcher 3 mod folder conventions once confirmed from StoryBoardUI and other installed mods.
- Use Git commits to capture meaningful milestones after the initial project structure and later implementation phases.
- Keep this file updated whenever new APIs, constraints, or implementation decisions are discovered.

## Open Research Questions

1. What exact folder name and script structure should AutoDriver use for Witcher 3 script loading?
2. Which Witcher Script APIs can move the player character or simulate player input?
3. Which APIs can teleport the player, and what coordinate/world constraints apply?
4. How can mounted horse state be detected and controlled?
5. How are walk, jog, run, sprint, and horse speed tiers represented internally?
6. Is character model switching possible through script only, or does it require entity/template changes?
7. Is automatic combat feasible through high-level AI/action APIs, or only through input simulation?

## Research Log

### 2026-05-26: StoryBoardUI Movement-Related Interfaces

StoryBoardUI does not appear to directly implement automatic player walking or mounted wandering. Its movement-related code is mostly for:

- Moving an interactive camera.
- Moving and rotating spawned storyboard actors/items.
- Teleporting entities to stored placements.
- Freezing/unfreezing actors and forcing idle behavior so storyboard actors stay in place.

Potentially useful interfaces and patterns:

- `AddTimer('updateInteractiveSettings', 0.015f, true, , , , true)` and `RemoveTimer(...)` are used to run frequent movement update loops.
- `theInput.GetActionValue('ActionName')` reads action axis values for continuous movement or rotation.
- `theInput.RegisterListener(this, 'HandlerName', 'ActionName')` and `theInput.UnregisterListener(...)` are used for hotkey/action callbacks.
- `CEntity.TeleportWithRotation(pos, rot)` moves an entity and sets rotation.
- `CEntity.Teleport(pos)` moves an entity without rotation.
- `CEntity.GetWorldPosition()` and `CEntity.GetWorldRotation()` read current transform.
- `thePlayer.GetWorldPosition()` and `thePlayer.GetWorldRotation()` are used as valid spawn/origin positions.
- `theGame.GetWorld().NavigationComputeZ(pos, minZ, maxZ, out groundZ)` and `PhysicsCorrectZ(pos, out groundZ)` are used to snap placements to valid ground height.
- `CActor.GetMovingAgentComponent().GetMovementAdjustor()` plus `CreateNewRequest(...)`, `Continuous(...)`, and `RotateTo(...)` are used to force actor facing after teleport/placement.
- `CActor.SetBehaviorVariable('requestedFacingDirection', yaw)` is used before unfreezing actor pose.
- `CActor.ForceAIBehavior(new CAIIdleTree in actor, BTAP_AboveCombat)` is used to force spawned actors to stay idle.

Relevant StoryBoardUI files:

- `modStoryboardUi\content\scripts\local\workmodes\camera_mode.ws`
  - `CStoryBoardInteractiveCamera.updateInteractiveSettings(...)` reads movement input, computes forward/left vectors from heading, and calls `TeleportWithRotation`.
  - `OnChangeSpeed(...)` switches movement/rotation step sizes for fast/slow controls.
- `modStoryboardUi\content\scripts\local\workmodes\placement_mode.ws`
  - `CModStoryBoardInteractivePlacement.updateInteractiveSettings(...)` moves selected assets relative to camera heading, optionally snaps to ground, and calls `asset.setPlacement(...)`.
  - `OnChangePlacementSpeed(...)` likely contains another fast/slow step-size pattern.
- `modStoryboardUi\content\scripts\local\shotviewer\storyboardasset.ws`
  - `CModStoryBoardAsset.setPlacement(...)` calls `entity.TeleportWithRotation(...)`.
  - `CModStoryBoardActor.preventBehTreeRotation(...)` uses `CMovementAdjustor` to keep actor yaw after teleport.
  - `CModStoryBoardActor.spawn(...)` shows actor setup, collision changes, temporary friendly attitude, and idle AI forcing.
- `modStoryboardUi\content\scripts\local\shotviewer\placement_director.ws`
  - `refreshDefaultPlacement(...)` uses player position as a valid origin and corrects Z with world navigation/physics helpers.

Current implication for AutoDriver:

- StoryBoardUI gives good implementation patterns for timers, input bindings, teleporting, ground correction, speed tiers, and actor rotation.
- It does not yet reveal a high-level "walk player to target" or "wander mounted horse" API.
- Next research should inspect base game scripts or other mods for `W3PlayerWitcher`, horse/mount classes, locomotion/AI movement requests, and possible input simulation APIs.

### 2026-05-27: Base Game Movement And Horse Interfaces

Base game scripts are available locally at:

```text
E:\SteamLibrary\steamapps\common\The Witcher 3\content\content0\scripts
```

High-value movement interfaces found in base game scripts:

- `scripts\game\actor.ws`
  - `ActionMoveTo(target : Vector, optional moveType : EMoveType, optional absSpeed : float, optional radius : float, optional failureAction : EMoveFailureAction) : bool`
  - `ActionMoveToAsync(...)`
  - `ActionMoveToWithHeading(target : Vector, heading : float, optional moveType : EMoveType, optional absSpeed : float, optional radius : float, optional failureAction : EMoveFailureAction) : bool`
  - `ActionMoveToWithHeadingAsync(...)`
  - `ActionCancelAll()`
  - `GetMovingAgentComponent() : CMovingAgentComponent`
  - `IsUsingHorse(optional ignoreMountInProgress : bool) : bool`
  - `GetUsedHorseComponent() : W3HorseComponent`
  - `FindAndMountVehicle(optional mountType : EVehicleMountType, optional maxDistance : float) : bool`
- `scripts\game\components\movingAgentComponent.ws`
  - `SetMoveType(moveType : EMoveType)`
  - `GetCurrentMoveSpeedAbs()`
  - `GetSpeed()`
  - `GetRelativeMoveSpeed()`
  - `GetMoveTypeRelativeMoveSpeed(moveType : EMoveType)`
  - `ForceSetRelativeMoveSpeed(relativeMoveSpeed : float)`
  - `SetGameplayRelativeMoveSpeed(relativeMoveSpeed : float)`
  - `SetGameplayMoveDirection(actorDirection : float)`
  - `SetDirectionChangeRate(directionChangeRate : float)`
  - `CanGoStraightToDestination(destination : Vector) : bool`
  - `IsPositionValid(position : Vector) : bool`
  - `GetEndOfLineNavMeshPosition(pos : Vector, out outPos : Vector) : bool`
  - `SnapToNavigableSpace(snap : bool)`
  - `GetMovementAdjustor() : CMovementAdjustor`

Existing vanilla wander implementation:

- `scripts\game\behavior_tree\tasks\movement\btTaskWander.ws`
  - `CBTTaskWander.Main()` chooses `whereTo = initialPos + VecRingRand(minDistance, maxDistance)`.
  - It randomizes `absSpeed = RandRangeF(maxSpeed, minSpeed)`.
  - It moves with `actor.ActionMoveTo(whereTo, moveType, absSpeed)`.
  - Default wander values: `minDistance = 4.0`, `maxDistance = 12.0`, `minSpeed = 0.2`, `maxSpeed = 2.0`, `moveType = MT_Run`.

This is the best current template for AutoDriver's walking wander logic. First implementation candidate:

1. Pick a random ring offset around the player.
2. Correct the destination with `NavigationComputeZ` / `PhysicsCorrectZ` and/or `CMovingAgentComponent.IsPositionValid`.
3. Call `thePlayer.ActionMoveToAsync(destination, selectedMoveType, selectedAbsSpeed, radius)`.
4. Cancel/reissue with `thePlayer.ActionCancelAll()` when toggling AutoDriver off or choosing a new target.

Player locomotion speed model:

- `scripts\game\player\movement\locomotionDirectController.ws`
  - Player input is read from `theInput.GetActionValue('GI_AxisLeftX')` and `theInput.GetActionValue('GI_AxisLeftY')`.
  - The controller ultimately writes movement with:
    - `movingAgentComponent.SetGameplayRelativeMoveSpeed(moveSpeed)`
    - `movingAgentComponent.SetGameplayMoveDirection(worldMoveDirection)`
    - `movingAgentComponent.SetDirectionChangeRate(10000.0f)`
  - Default relative speed thresholds:
    - `speedSlowWalkingMax = 0.3`
    - `speedWalkingMax = 0.6`
    - `speedRunning = 1.0`
    - `speedSprinting = 1.5`
    - `speedSprintingWithPerk = 1.6`
- `scripts\game\player\playerTypes.ws`
  - `EPlayerMoveType`: `PMT_Idle`, `PMT_Walk`, `PMT_Run`, `PMT_Sprint`.

This suggests a second possible AutoDriver control strategy: bypass real input and directly set `SetGameplayRelativeMoveSpeed(...)` plus `SetGameplayMoveDirection(...)` in a timer. This may be useful for continuous "drive forward" behavior, but it may fight the player's normal locomotion controller unless AutoDriver hooks into or disables normal input logic. `ActionMoveToAsync` is likely safer for the first walking prototype.

Horse and mounted movement findings:

- `scripts\game\actor.ws`
  - `IsUsingHorse(true)` checks for fully mounted state only.
  - `GetUsedHorseComponent()` returns the active `W3HorseComponent`.
- `scripts\game\vehicles\horse\horseComponent.ws`
  - `W3HorseComponent` owns horse-specific speed and state.
  - `InternalSetSpeed(value)` calls the horse actor's `GetMovingAgentComponent().SetGameplayRelativeMoveSpeed(value)` and stores the `speed` variable.
  - `InternalGetSpeed()` reads the horse actor's relative move speed.
  - `InternalSetDirection(value)` and `InternalSetRotation(value)` set horse behavior variables.
  - `SetManualControl(val : bool)` exists.
- `scripts\game\vehicles\horse\states\exploration.ws`
  - Horse speed constants:
    - `MIN_SPEED = 0`
    - `SLOW_SPEED = 0.5`
    - `WALK_SPEED = 1`
    - `TROT_SPEED = 2`
    - `GALLOP_SPEED = 3`
    - `CANTER_SPEED = 4`
  - The horse state listens to actions `Canter`, `Gallop`, `Decelerate`, `Stop`, `HorseJump`, `HorseDismount`, and `HorseKick`.
  - Horse direction/rotation is normally driven through `InternalSetDirection(...)` and `InternalSetRotation(...)`.
  - `parent.InternalSetSpeed(currSpeed)` applies the current horse speed.
  - `MaintainCameraVariables()` maps `currSpeed == CANTER_SPEED` to `inCanter` and `currSpeed == GALLOP_SPEED` to `inGallop`.
- `scripts\game\player\states\vehicles\useVehicle.ws`
  - `ContinuedState()` teleports the vehicle entity to `parent.GetWorldPosition()` and remounts with `vehicle.Mount(parent, VMT_ImmediateUse, EVS_driver_slot)`.
- `scripts\game\player\r4Player.ws`
  - `MountVehicle(vehicleEntity, mountType, optional vehicleSlot)` wraps `CVehicleComponent.Mount(...)`.
  - `DismountVehicle(vehicleEntity, dismountType)` wraps `CVehicleComponent.IssueCommandToDismount(...)`.
- `scripts\game\vehicles\vehicleComponent.ws`
  - Mount modes include `VMT_ApproachAndMount`, `VMT_TeleportAndMount`, `VMT_MountIfPossible`, and `VMT_ImmediateUse`.

Mounted AutoDriver implications:

- Detect mounted state with `thePlayer.IsUsingHorse(true)`.
- Get horse component with `thePlayer.GetUsedHorseComponent()`.
- Get horse actor/entity from the horse component when needed.
- For random mounted teleport, likely teleport the horse/vehicle entity and let the mounted rider follow, or teleport both carefully. The `UseGenericVehicle.ContinuedState()` pattern suggests the game can remount after teleporting the vehicle to the player, but this needs in-game testing.
- For mounted wander, possible approaches:
  - Use horse component's speed/direction methods (`InternalSetSpeed`, `InternalSetDirection`, `InternalSetRotation`) if accessible from mod code.
  - Use the horse actor's `ActionMoveToAsync(...)` or `CMovingAgentComponent` directly.
  - Simulate/trigger horse actions (`Canter`, `Gallop`, etc.) if input/action injection is possible.

Open risks after base-script search:

- `ActionMoveToAsync` is defined on `CActor`, and `thePlayer` is a `CR4Player`/`W3PlayerWitcher`, so it should be callable, but it may conflict with player state logic. Needs a minimal prototype.
- Direct `SetGameplayRelativeMoveSpeed` may be overwritten every frame by `CR4LocomotionPlayerControllerScript.UpdateLocomotion()`.
- Some horse methods are `final function` inside `W3HorseComponent`; they may be callable from mod code if visibility permits, but this must be compile-tested.
- Horse random teleport while mounted should be tested conservatively because rider/vehicle attachment state can break if only one entity is moved.

### 2026-05-27: First AutoDriver Wander Prototype

Created the first prototype script:

```text
AutoDriver\content\scripts\local\mod_autodriver.ws
```

Created input bindings:

```text
AutoDriver\AutoDriver.input.settings
```

Hotkeys:

- `IK_NumPad3` -> `AutoDriver_WalkWander`
- `IK_NumPad2` -> `AutoDriver_HorseWander`

Bootstrap registration:

- `modBootstrap-registry\content\scripts\local\mods_registry.ws` was updated to call `add(createAutoDriver());`.
- The existing StoryBoardUI registration was preserved.

Prototype design:

- `CModAutoDriver` is a bootstrapped `CMod` statemachine.
- `AutoDriver_WalkWander` repeatedly picks a random ground-corrected destination around the player and calls `thePlayer.ActionMoveTo(...)`.
- `AutoDriver_HorseWander` requires `thePlayer.IsUsingHorse(true)`, gets the current mounted vehicle as a `CActor`, and calls `horse.ActionMoveTo(...)`.
- Toggling either mode off calls `ActionCancelAll()` on `thePlayer` and on the horse actor when mounted.
- Walking speed is fixed at `MT_Run` with absolute speed `1.0`.
- Horse speed is fixed at `MT_Run` with absolute speed `2.0`.

What this prototype is meant to validate:

1. Whether `thePlayer.ActionMoveTo(...)` works for player-controlled Geralt in exploration.
2. Whether calling `ActionMoveTo(...)` on the mounted horse actor works while the player is attached.
3. Whether bootstrap + input registration is sufficient for the hotkeys to control AutoDriver.

Known risks:

- The game may reject `ActionMoveTo(...)` on the player if the player locomotion state overrides AI movement.
- The mounted horse may ignore actor-level `ActionMoveTo(...)` because horse exploration state normally manages speed/direction internally.
- If the `AutoDriver` folder name is not picked up by the game's mod loader, it may need to be renamed or mirrored as a conventional `modAutoDriver` folder.

### 2026-06-01: Fix Mod Loader Visibility

First in-game compile attempt failed with:

```text
Error [modbootstrap-registry]local\mods_registry.ws(10): Could not find function 'createAutoDriver'
```

Diagnosis:

- `modBootstrap-registry` was correctly calling `add(createAutoDriver());`.
- The error means the global `createAutoDriver()` function from `AutoDriver\content\scripts\local\mod_autodriver.ws` was not visible to the compiler.
- The likely cause is that the folder was named `AutoDriver`, while Witcher 3 mod folders conventionally use names beginning with `mod`.

Fix applied:

- Created a directory junction:

```text
E:\SteamLibrary\steamapps\common\The Witcher 3\mods\modAutoDriver -> E:\SteamLibrary\steamapps\common\The Witcher 3\mods\AutoDriver
```

- Added `modAutoDriver.input.settings` alongside the existing `AutoDriver.input.settings`.
- Kept the actual Git repository and source of truth in `AutoDriver`.

Expected result:

- The game should now discover the scripts through the `modAutoDriver` loader-visible path.
- `createAutoDriver()` should be available when `modBootstrap-registry` compiles.

### 2026-06-01: Fix Latent Return Compile Error

Second in-game compile attempt failed with:

```text
Error [modautodriver]local\mod_autodriver.ws(91): Function 'moveActorRandom' - latent calls not allowed in return statement
```

Diagnosis:

- `CActor.ActionMoveTo(...)` is a latent function.
- WitcherScript does not allow latent calls directly inside a `return` statement.

Fix applied:

```witcherscript
result = actor.ActionMoveTo(whereTo, moveType, absSpeed, 1.5);
return result;
```

Expected result:

- The compiler should get past `moveActorRandom`.

### 2026-06-01: Merge AutoDriver Input Bindings

Runtime observation:

- AutoDriver displayed the startup HUD message in game, so bootstrap creation succeeded.
- Pressing `NumPad2` / `NumPad3` produced no visible response.

Diagnosis:

- This indicates the mod instance exists, but the input actions were probably not bound in the live user input configuration.
- `Documents\The Witcher 3\input.settings` contained StoryBoardUI's `IK_F7=(Action=SBUI_Maximize)` binding but did not contain any `AutoDriver_*` actions.
- Therefore the mod-local `modAutoDriver.input.settings` file was not enough by itself for this installed setup; the live `input.settings` needed to be merged.

Fix applied:

- Backed up the live input file to:

```text
C:\Users\64617\Documents\The Witcher 3\input.settings.backup-before-AutoDriver-20260601-160411
```

- Added these bindings to `[Exploration]` and `[Exploration_Replacer_Ciri]` in:

```text
C:\Users\64617\Documents\The Witcher 3\input.settings
```

Bindings:

```text
IK_NumPad3=(Action=AutoDriver_WalkWander)
IK_NumPad2=(Action=AutoDriver_HorseWander)
```

Expected result:

- Pressing `NumPad3` while dismounted should now trigger the walk wander toggle and show a HUD message.
- Pressing `NumPad2` while mounted should now trigger the horse wander toggle and show a HUD message.
- If HUD messages appear but movement does not happen, the next issue is likely `ActionMoveTo(...)` or destination validity rather than input binding.

### 2026-06-01: Walk Wander Async Retarget Prototype

Runtime observation:

- `NumPad3` walk wander can move the player, confirming that `thePlayer.ActionMoveTo(...)` can work in exploration.
- The movement stops after roughly 20 seconds even while AutoDriver remains enabled.

Diagnosis:

- The first walk prototype used a latent `ActionMoveTo(...)` call inside the state loop.
- This made each loop iteration depend on the engine's one-shot movement action completing, timing out, or being interrupted.
- For continuous data collection, AutoDriver should instead keep its own movement state and reissue destinations when the current destination is reached or considered stale.

Fix applied:

- Added persistent walk target state:
  - `hasWalkTarget`
  - `currentWalkTarget`
  - `walkTargetIssuedAt`
- Added walk tuning values:
  - `walkArrivalDistance = 3.0`
  - `walkTargetTimeout = 10.0`
  - `walkTickInterval = 0.5`
- Changed walk wander to use `thePlayer.ActionMoveToAsync(...)`.
- The walk loop now:
  1. Issues a random navmesh-corrected target when no target exists.
  2. Checks every `0.5` seconds whether the player is within `3.0` meters of the target.
  3. Reissues a new random target when the target is reached.
  4. Reissues a new random target if the current target is older than `10.0` seconds.
- Stopping or switching states resets the stored walk target and cancels player actions.

Expected result:

- `NumPad3` should produce longer continuous walking/running behavior than the first prototype.
- If the player gets stuck or the engine silently drops a movement action, the timeout should recover by issuing a fresh target.
- This version only changes walk wander. Horse wander still uses the original blocking `ActionMoveTo(...)` prototype and should be upgraded separately after walk behavior is validated.

### 2026-06-01: Walk Wander Stuck Recovery

Runtime observation:

- Walk wander still has obvious stuck cases.
- Waiting longer than one minute did not visibly recover by issuing a new useful movement target.

Diagnosis:

- The previous async retarget version only tracked target age and distance to the target.
- It did not verify whether the player was actually making world-position progress.
- On timeout it also called `ActionMoveToAsync(...)` directly without explicitly cancelling the previous move action first.
- If the engine kept the old movement action active internally, the new async move request could fail, be ignored, or be unable to take control.

Fix applied:

- Added progress tracking:
  - `lastWalkPosition`
  - `lastWalkProgressAt`
  - `walkStuckDistance = 0.75`
  - `walkStuckTimeout = 3.0`
- The walk loop now updates actual player progress every `0.5` seconds.
- If the player has not moved at least `0.75` meters within `3.0` seconds, AutoDriver treats the current move as stuck.
- Every new walk target now first calls `thePlayer.ActionCancelAll()` before `ActionMoveToAsync(...)`.
- Target age timeout was reduced from `10.0` seconds to `8.0` seconds.

Expected result:

- If Geralt runs into terrain, props, or an unreachable path edge, AutoDriver should recover within a few seconds by cancelling the old move and issuing a new random target.
- This still uses action-based navigation. If the player controller itself stops accepting actor actions after some state transition, the next candidate approach is direct locomotion control through `SetGameplayRelativeMoveSpeed(...)` and `SetGameplayMoveDirection(...)`.

### 2026-06-01: Safer Walk Targets And Direct Wander Experiment

User direction:

- Continue the short-term stable path on `NumPad3`.
- Add the medium-term exploration path on `NumPad4`.

Short-term `NumPad3` changes:

- `AutoDriver_WalkWander` still uses `thePlayer.ActionMoveToAsync(...)`.
- Target selection now generates multiple candidates instead of trusting a single random point.
- Each candidate is processed with:
  - `randomGroundPosition(...)`
  - `theGame.GetWorld().NavigationFindSafeSpot(...)`
  - `CMovingAgentComponent.IsPositionValid(...)`
  - `CMovingAgentComponent.CanGoStraightToDestination(...)`
  - `CWorld.NavigationLineTest(...)`
- If a strong direct candidate is not found, the first safe valid fallback candidate is used.

Medium-term `NumPad4` experiment:

- Added `AutoDriver_DirectWander`.
- This mode does not call `ActionMoveToAsync(...)`.
- It repeatedly drives the player moving agent directly with:
  - `SetGameplayRelativeMoveSpeed(directSpeed)`
  - `SetGameplayMoveDirection(VecHeading(target - playerPosition))`
  - `SetDirectionChangeRate(10000.0f)`
- It uses the same safer target finder as `NumPad3`.
- It retargets on arrival, after `5.0` seconds, or if actual player position does not progress for `2.0` seconds.

Input bindings:

- `NumPad2`: horse wander prototype.
- `NumPad3`: safer action-based walk wander.
- `NumPad4`: direct locomotion wander experiment.
- The live user input file was updated at:

```text
C:\Users\64617\Documents\The Witcher 3\input.settings
```

Current risk:

- `NumPad4` is intentionally experimental. The player locomotion controller may overwrite direct moving-agent values every frame, but the loop writes them at a high frequency to test whether this control path is viable.

### 2026-06-01: NPC Camera Follow Experiments

Runtime observation:

- `NumPad3` safer action-based wander still gets stuck easily.
- `NumPad4` direct moving-agent wander does not move the player at all, which suggests the player locomotion controller overwrites or ignores this control path.

New fallback direction:

- Instead of forcing Geralt to move, let the game's existing town/community NPC AI provide the movement.
- AutoDriver can then switch or drive the camera to follow a nearby moving NPC.

Implemented experiments:

- `NumPad5`: `AutoDriver_CameraFollowNpc`
  - Finds a nearby moving alive actor with `GetActorsInRange(...)`.
  - Uses `CActor.IsMoving()` or moving-agent velocity as the moving check.
  - Calls `theGame.GetGameCamera().FollowWithRotation(npc)`.
  - Calls `LookAt(npc, 0.2f, 0.0f)` and activates the game camera.
  - Retargets if the selected NPC stops moving or gets too far away.
- `NumPad6`: `AutoDriver_StaticCameraFollowNpc`
  - Finds a nearby moving NPC using the same selector.
  - Creates a `CStaticCamera` from StoryBoardUI's installed `interactive_camera.w2ent` template.
  - Runs that static camera and updates it every `0.05` seconds.
  - Places the camera behind the NPC and points it toward the NPC with `VecToRotation(...)`.
  - Retargets if the selected NPC stops moving or gets too far away.

Input bindings:

- `NumPad5`: current game camera follows moving NPC.
- `NumPad6`: AutoDriver-controlled static camera follows moving NPC.

Current risk:

- `NumPad5` may be overridden by the normal player camera stack.
- `NumPad6` currently depends on StoryBoardUI's camera entity template being installed at:

```text
dlc\modtemplates\storyboardui\interactive_camera.w2ent
```

### 2026-06-02: NPC Camera Fallback And Smoothing

Runtime observation:

- Pressing `NumPad5` showed `could not get top camera`.
- Pressing `NumPad6` followed a nearby NPC, but the camera visibly jittered.

Diagnosis:

- `NumPad5` tried to cast `theCamera.GetTopmostCameraObject()` to `CCamera`.
- In the normal exploration camera stack the top camera object can be a `CCustomCamera`, so the cast fails and the direct `FollowWithRotation(...)` route is not available.
- `NumPad6` updated camera transform with hard `TeleportWithRotation(...)` every `0.05` seconds.
- NPC heading/animation/velocity changes can fluctuate slightly every frame, and hard teleporting directly to those values amplifies the shake.

Fix applied:

- `NumPad5` now automatically falls back to the static NPC camera route when no usable top `CCamera` is available.
- Added camera smoothing state:
  - `npcCamSmoothingInitialized`
  - `smoothedNpcCamPos`
  - `smoothedNpcCamRot`
  - `npcCamPositionSmooth = 5.0`
  - `npcCamRotationSmooth = 7.0`
- `NumPad6` now interpolates camera position with `LerpV(...)`.
- `NumPad6` now interpolates rotation pitch/yaw/roll with `LerpAngleF(...)`.
- The follow direction uses NPC velocity when moving, falling back to heading only when velocity is too small.

Expected result:

- `NumPad5` should no longer fail with `could not get top camera`; if direct follow is unavailable, it should report that it is using the static NPC camera fallback.
- `NumPad6` should still follow the same kind of moving NPC, but camera movement should be less twitchy.

### 2026-06-02: Official Movement Interface Re-scan

Runtime observation:

- Random nearby NPC camera follow is not stable enough for data capture.
- Town NPCs usually walk slowly, can stop for long periods, and may despawn when their community/encounter lifecycle ends.
- This makes "follow a random existing NPC" a useful diagnostic route, but not a good final capture driver.

Important official player movement findings:

- The base game has an official debug helper in `content0\scripts\game\temp.ws` named `MovePlayerFwd(distance, speed, ...)`.
- `MovePlayerFwd` does not use raw `ActionMoveTo(...)` directly on `thePlayer`.
- Instead it creates a `CAIMoveToPoint`, fills:
  - `params.moveSpeed`
  - `params.destinationHeading`
  - `params.destinationPosition`
  - `params.maxIterationsNumber`
  - `params.moveType`
- For player movement it wraps that scripted action in `CAIPlayerActionDecorator` and calls `ForceAIBehavior(..., BTAP_Emergency)`.
- `scenePlayer.ws` uses the same pattern for short scripted player walk actions during scenes.
- `r4Player.ws` also uses `CAIPlayerActionDecorator` with `CAIFollowSideBySideAction` / `CAIRiderFollowSideBySideAction` to force player or horse follow behavior.

Relevant official classes and files:

```text
content0\scripts\game\behavior_tree\ai_parameters\actionParams.ws
  CAIMoveToPoint
  CAIMoveToPointParams
  CAIPlayerActionDecorator
  CAIPlayerRiderActionDecorator

content0\scripts\game\temp.ws
  exec function MovePlayerFwd(...)

content0\scripts\game\scenes\scenePlayer.ws
  scripted scene walk actions using CAIMoveToPoint + CAIPlayerActionDecorator

content0\scripts\game\player\r4Player.ws
  ForceAIBehavior for player follow / rider follow
```

Important official NPC wander findings:

- Town/community NPC wandering is not just a random `Vector` plus `ActionMoveTo(...)`.
- Encounter/community setup uses SmartAI initializers:
  - `CSpawnTreeInitializerSmartWanderAI`
  - `CSpawnTreeInitializerSmartDynamicWanderAI`
  - `CSpawnTreeInitializerSmartWanderAndWorkAI`
- These install AI trees such as:
  - `CAIWanderWithHistory`
  - `CAIDynamicWander`
  - `CAINpcActiveIdle`
- This likely gives NPCs better integration with navmesh/action points/community areas than AutoDriver's current raw random target loop.

Relevant official NPC files:

```text
content0\scripts\game\gameplay\encounter\encounterInitializers.ws
content0\scripts\game\gameplay\encounter\entryGenerators\wanderEntriesGenerator.ws
content0\scripts\game\gameplay\encounter\entryGenerators\wanderAndWorkEntriesGenerator.ws
content0\scripts\game\behavior_tree\ai_parameters\npcParams.ws
```

Important StoryBoardUI route:

- StoryBoardUI provides a Geralt NPC clone template:

```text
dlc\modtemplates\storyboardui\geralt_npc.w2ent
```

- `storyboardasset.ws` has working code to:
  - load this template,
  - spawn it with `theGame.CreateEntity(...)`,
  - clone player's equipment to the spawned NPC,
  - disable collisions,
  - assign friendly attitude,
  - force an AI behavior with `ForceAIBehavior(...)`.

Implication:

- A strong next route is to spawn our own persistent Geralt-like NPC clone, then drive that clone with official NPC/player AI actions and attach the AutoDriver camera to it.
- This avoids two weaknesses of following random city NPCs:
  - no random despawn/lifecycle loss,
  - AutoDriver controls speed and destination policy.
- It also avoids some restrictions of the real player locomotion controller.

Recommended next experiments:

1. Replace or add a player wander test using official `CAIMoveToPoint + CAIPlayerActionDecorator`, modeled after `MovePlayerFwd`.
2. Add a spawned Geralt NPC clone test using StoryBoardUI's `geralt_npc.w2ent`, then drive that clone with `CAIMoveToPoint` or `CAIDynamicWander`.
3. Keep `ActionMoveCustomAsync + CMoveTRGScript` as a secondary experiment for continuous steering, because it gives direct per-frame speed/heading goals, but it is less proven on `thePlayer` than the official `CAIMoveToPoint` decorator route.

### 2026-06-02: Official Player Wander And Geralt Clone Experiment

Implemented:

- `NumPad3` still uses `AutoDriver_WalkWander`, but the movement backend was changed.
- The old `ActionMoveToAsync(...)` call was replaced with an official-style scripted action:
  - create `CAIMoveToPoint`
  - set destination, heading, speed, timeout, and move type
  - wrap with `CAIPlayerActionDecorator`
  - call `ForceAIBehavior(..., BTAP_Emergency)`
- This is modeled after the base-game `MovePlayerFwd(...)` debug helper in `content0\scripts\game\temp.ws` and scene movement usage in `scenePlayer.ws`.

Implemented clone experiment:

- `NumPad4` still uses the existing input action name `AutoDriver_DirectWander`, but the actual feature is now Geralt clone wander.
- It loads StoryBoardUI's template:

```text
dlc\modtemplates\storyboardui\geralt_npc.w2ent
```

- It spawns the clone in front of the player, disables collisions, sets a friendly attitude group, and tags it as `AutoDriverClone`.
- It uses AutoDriver's existing StoryBoardUI static camera path to follow the clone.
- It drives the clone by repeatedly issuing `CAIMoveToPoint` with `ForceAIBehavior(...)`.
- The clone is destroyed when the mode stops.

Current binding semantics:

- `NumPad3`: official-style player walk wander.
- `NumPad4`: Geralt NPC clone wander with static camera follow.

Known risks:

- The clone currently uses StoryBoardUI's template directly, but does not yet clone the player's equipment/appearance the way StoryBoardUI's full `CModStoryBoardActor.cloneFromPlayer(...)` path does.
- If the template cannot be loaded because StoryBoardUI's DLC resources are not installed or not mounted, `NumPad4` will report a template load failure.
- `NumPad4` currently uses `CAIMoveToPoint`; `CAIDynamicWander` remains a later experiment if clone movement still sticks too easily.

### 2026-06-02: WitcherScript Compile Notes

Observed compile error:

```text
Error [modautodriver]local\mod_autodriver.ws(819): Unable to convert from 'void' to 'Bool'
```

Cause:

- The failing line was a bare `return;` inside `event OnEnterState(...)`.
- WitcherScript can report this as a `void` to `Bool` conversion error in state/event contexts, even though the surrounding logic looks unrelated to a boolean conversion.

Rule learned:

- Avoid early bare `return;` inside `event OnEnterState(...)`.
- Prefer:

```witcherscript
if (!condition) {
    parent.GotoState('AutoDriver_Idle');
} else {
    WorkLoop();
}
```

- Keep `return;` in `entry function` loops only when it has already been proven to compile.

Related earlier compile note:

- Latent calls cannot be placed directly in a return statement. Store the result in a local variable first, then return that variable.

### 2026-06-02: NumPad7 And NumPad8 Player Movement Experiments

Implemented two new experiments without replacing the existing `NumPad3` and `NumPad4` behavior.

`NumPad7`: tuned `CAIMoveToPoint` player wander

- Action name: `AutoDriver_TunedMovePointWander`.
- Uses the same official-style player route as `NumPad3`:
  - `CAIMoveToPoint`
  - `CAIPlayerActionDecorator`
  - `ForceAIBehavior(..., BTAP_Emergency)`
- Differences from `NumPad3`:
  - shorter target distance: `3.0` to `7.0`
  - `maxIterationsNumber = 8`
  - `interruptOnInput = false`
  - lower reissue cadence: `1.5` seconds
  - target timeout: `12.0` seconds
  - arrival distance: `1.4`
- Goal: test whether the official scripted move action can become continuous enough when it is not constantly interrupted/reissued.

`NumPad8`: custom `CMoveTRGScript` seek wander

- Action name: `AutoDriver_CustomSeekWander`.
- Adds `CAutoDriverMoveTRGSeek extends CMoveTRGScript`.
- Each locomotion update:
  - checks distance to target,
  - calls `Seek(target)` for heading,
  - calls `SetSpeedGoal(...)`,
  - calls `SetHeadingGoal(...)`,
  - calls `SetOrientationGoal(...)`,
  - calls `MatchDirectionWithOrientation(...)`.
- Movement is started with `thePlayer.ActionMoveCustomAsync(targeter)`.
- Goal: test whether a continuous locomotion targeter works better than one-shot scripted actions.

Input updates:

- Added `IK_NumPad7=(Action=AutoDriver_TunedMovePointWander)`.
- Added `IK_NumPad8=(Action=AutoDriver_CustomSeekWander)`.
- Updated both mod input files and the live file:

```text
C:\Users\64617\Documents\The Witcher 3\input.settings
```

Risks:

- `ActionMoveCustomAsync(...)` may still be blocked or overwritten by the real player exploration controller.
- `CMoveTRGScript` compiles in base game behavior-tree tasks, but this is AutoDriver's first custom top-level targeter, so syntax or engine ownership issues may appear during game script compilation.

### 2026-07-12: God Mode And Teleport Initial Implementation

Development plan:

```text
GOD_TELEPORT_DEVELOPMENT_PLAN.md
```

Implemented bindings:

- `NumPad7`: `AutoDriver_GodMode`
- `NumPad8`: `AutoDriver_OfficialTeleport`
- `NumPad9`: `AutoDriver_RandomXYTeleport`

`NumPad7` implementation:

- Toggles `AIM_Invulnerable` on AutoDriver's `AIC_Default` channel.
- Does not enable unlimited stamina, global negative-buff immunity, or hit-animation suppression.
- Runs an independent repeating timer every `0.25` seconds.
- The timer fills `BCS_Air` to its current maximum and removes `EET_Drowning` if present.
- Disabling the mode removes the timer and restores `AIM_None` on `AIC_Default`.

`NumPad8` implementation:

- Uses `GetFastTravelPoints(false, false, false, false, false)` with no filtering.
- Traverses the complete returned list sequentially.
- Stores the next list index in the persistent fact:

```text
autodriver_official_teleport_index
```

- Uses each pin's type to resolve either a `RoadSign` or `Harbor` teleport waypoint.
- Uses `TeleportWithRotation(...)` for destinations in the current world.
- Uses `ScheduleWorldChangeToPosition(...)` for resolved cross-world destinations.
- Uses `ScheduleWorldChangeToMapPin(...)` as the official cross-world fallback when position lookup fails.
- Logs index, total, tag, type, area, world path, resolution state, and destination position.
- Refuses teleport during combat, gameplay/non-gameplay scenes, horse riding, sailing, or boat use.

`NumPad9` implementation:

- Remains in the current world.
- Selects a random current-world `RoadSign` as a safe anchor.
- Teleports to the anchor and waits `2.0` seconds for streaming/navigation data.
- Generates up to `20` random candidates between `20` and `100` units from the anchor.
- Validates with `NavigationFindSafeSpot`, `NavigationComputeZ`, a second `NavigationFindSafeSpot`, moving-agent `IsPositionValid`, and optional `PhysicsCorrectZ`.
- Does not brute-force a failed destination; the player remains at the safe anchor if validation fails.
- Uses a dedicated temporary state to reject repeated input while the two-stage teleport is running.

Input files updated:

```text
AutoDriver.input.settings
modAutoDriver.input.settings
C:\Users\64617\Documents\The Witcher 3\input.settings
```

Pending validation:

- WitcherScript compilation in game.
- God-mode damage and long-duration diving behavior.
- Sequential cursor persistence after cross-world loading.
- Harbor destination safety while on foot.
- Random XY behavior across major worlds and terrain types.
# 2026-07-13: Timer API ownership correction

- `AddTimer` and `RemoveTimer` are `CEntity` methods, not global functions.
- `CModAutoDriver extends CMod extends IScriptable`, so direct timer calls in the mod class do not compile.
- StoryBoardUI's direct timer calls occur in entity-derived classes and cannot be copied into `CModAutoDriver` without preserving that ownership model.
- Calling `thePlayer.AddTimer` is not a drop-in fix because the timer callback must exist on the timer-owning entity.
- The invalid oxygen maintenance timer was removed to restore compilation. Health invulnerability still protects against drowning damage; persistent oxygen replenishment needs a verified entity helper or effect-layer implementation.

# 2026-07-13: God-mode equipment durability protection

- `NumPad7` now protects every durability-bearing item currently in the player's inventory by adding the official `MA_Indestructible` crafted ability.
- AutoDriver writes the item modifier `AutoDriverIndestructible = 1` only when it adds that ability.
- Disabling god mode removes `MA_Indestructible` only from marked items, preserving equipment that was inherently indestructible before AutoDriver touched it.
- Mod initialization clears stale marked protections left by saving or exiting while god mode was enabled.
- Existing durability is not repaired. The feature prevents subsequent durability loss while enabled.
- Items acquired after god mode is enabled are not protected until god mode is toggled off and on again.

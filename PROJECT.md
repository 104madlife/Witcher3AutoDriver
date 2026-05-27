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

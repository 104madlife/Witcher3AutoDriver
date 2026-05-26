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

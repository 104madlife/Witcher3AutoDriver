# AutoDriver God Mode And Teleport Development Plan

Date: 2026-07-12

Status: Initial implementation completed on 2026-07-12; pending in-game script compilation and runtime validation.

## 1. Scope

This phase replaces the current experimental meanings of `NumPad7` and `NumPad8` and adds `NumPad9`.

| Key | Feature | Required behavior |
| --- | --- | --- |
| `NumPad7` | God mode toggle | Toggle health damage immunity and equipment durability protection; refill oxygen once when enabled. |
| `NumPad8` | Official stable teleport | Teleport once per press through the complete official fast-travel-point list, including cross-world destinations, with no discovery, enabled-state, type, or area filtering. |
| `NumPad9` | Random XY teleport | Generate and validate a random destination in the current world only. |

`NumPad6` is additionally assigned to an official-style horse mount/dismount toggle. `NumPad8` and `NumPad9` automatically perform and confirm an instant dismount before teleporting when the player is mounted.

The old `NumPad7` tuned-move experiment and `NumPad8` custom-seek experiment will no longer be bound to those keys. Their code may remain temporarily for comparison, but must not run from the new bindings.

## 2. Confirmed Base-Game Interfaces

### 2.1 Health invulnerability

The base game implements its own `god()` command using:

```witcherscript
thePlayer.SetImmortalityMode(AIM_Invulnerable, AIC_Default, true);
```

Disable with:

```witcherscript
thePlayer.SetImmortalityMode(AIM_None, AIC_Default, true);
```

`W3PlayerWitcher.ReduceDamage(...)` checks `IsInvulnerable()` and sets all processed damage to zero. AutoDriver will use only this part of the official god command. It will not enable unlimited stamina, suppress all hit animations, or grant blanket immunity to all negative buffs unless later requested.

Known limitation: damage actions explicitly marked `ignoreImmortalityMode` can bypass this mode. These are expected to be exceptional scripted/quest actions rather than normal combat damage.

### 2.2 Oxygen and drowning

Underwater air is the base character stat `BCS_Air`.

The official quest helper `SetPlayerOxygen(100, false)` ultimately performs:

```witcherscript
thePlayer.ForceSetStat(BCS_Air, thePlayer.GetStatMax(BCS_Air));
```

The diving air-drain effect continuously reduces `BCS_Air`. When it reaches zero, it adds `EET_Drowning`. The drowning effect remains active until air becomes positive or the player stops diving.

Recommended implementation while god mode is enabled:

1. Run an independent repeating oxygen-maintenance timer, not a locomotion state.
2. Every `0.25` to `0.5` seconds, set `BCS_Air` to its current maximum.
3. If `EET_Drowning` is already present when god mode is enabled, remove it once immediately.
4. Optionally remove `EET_Drowning` again in the maintenance callback as defensive cleanup.
5. When god mode is disabled, stop the timer. Do not reduce oxygen; normal draining resumes naturally from the current value.

This approach keeps the oxygen bar full and prevents the drowning visual/no-save-lock lifecycle. It is preferable to `AddBuffImmunity_AllNegative(...)`, which would alter many unrelated gameplay effects.

### 2.3 Official fast-travel list and teleport

Retrieve every official fast-travel point with no filtering:

```witcherscript
pins = theGame.GetCommonMapManager().GetFastTravelPoints(
    false, false, false, false, false
);
```

Each `SAvailableFastTravelMapPin` contains:

- `tag`: destination entity/map-pin tag.
- `type`: normally `RoadSign` or `Harbor`.
- `area`: destination `EAreaName`.

The map manager can resolve a pin to its dedicated teleport waypoint position and rotation. This is safer than using the visible map-pin position.

For a destination in the current world:

```witcherscript
thePlayer.TeleportWithRotation(position, rotation);
```

For a destination in another world:

```witcherscript
theGame.ScheduleWorldChangeToPosition(worldPath, position, rotation);
```

If the destination position cannot be resolved, the official fallback is:

```witcherscript
theGame.ScheduleWorldChangeToMapPin(worldPath, pin.tag);
```

## 3. NumPad7 Design: Invulnerability, Oxygen, And Equipment Durability

### Equipment durability extension

- On enable, scan all durability-bearing items currently in the player inventory.
- Add the official `MA_Indestructible` crafted ability only to items that do not already have it.
- Mark AutoDriver-owned changes with `AutoDriverIndestructible = 1` using the item modifier API.
- On disable or mod initialization, remove the ability only from marked items and clear the marker.
- Do not repair durability that was already lost, and do not alter inherently indestructible items.

### 3.1 State owned by AutoDriver

Add a dedicated boolean such as `godModeEnabled`. Do not infer ownership only from `thePlayer.IsInvulnerable()`, because quests or other mods may independently set another immortality channel.

AutoDriver will own only `AIC_Default`, matching the official `god()` command.

### 3.2 Enable sequence

1. Set `godModeEnabled = true`.
2. Call `SetImmortalityMode(AIM_Invulnerable, AIC_Default, true)`.
3. Fill `BCS_Air` to `GetStatMax(BCS_Air)`.
4. Remove an existing `EET_Drowning` effect if present.
5. Start the repeating oxygen-maintenance timer.
6. Show a HUD message confirming health invulnerability and unlimited oxygen are enabled.

### 3.3 Disable sequence

1. Set `godModeEnabled = false`.
2. Stop/remove the oxygen-maintenance timer.
3. Call `SetImmortalityMode(AIM_None, AIC_Default, true)`.
4. Leave current oxygen unchanged.
5. Show a HUD message confirming the mode is disabled.

### 3.4 Persistence and lifecycle

- On mod initialization or player/world replacement, do not silently assume the old player entity still owns the mode.
- First version may reset the toggle to off after game/mod reload.
- Cross-world travel must be tested because `thePlayer` can be replaced during loading. If the toggle is intended to survive world changes, reapply invulnerability and restart oxygen maintenance after the new player entity is available.
- Do not use the main AutoDriver state machine for oxygen maintenance; otherwise pressing another feature key could accidentally disable oxygen maintenance.

### 3.5 Validation

- Receive normal melee damage: health must not decrease.
- Receive fall damage: health should not decrease.
- Dive until longer than the normal oxygen duration: oxygen must remain full and `EET_Drowning` must not remain active.
- Disable while underwater: oxygen should begin draining normally again.
- Toggle repeatedly: no duplicate timers and no immortality-channel lock conflict.

## 4. NumPad8 Design: Complete Official Fast-Travel Test

### 4.1 Enumeration policy

The first version must include every point returned by:

```witcherscript
GetFastTravelPoints(false, false, false, false, false)
```

No exclusions will be applied for:

- discovered state;
- enabled/disabled state;
- `RoadSign` versus `Harbor`;
- Velen or winter-prologue duplicates;
- current versus other world.

### 4.2 Test order

Use deterministic sequential traversal rather than random selection so every returned point can be tested.

Maintain a cursor `officialTeleportIndex`:

1. Build or refresh the complete list.
2. Select `pins[officialTeleportIndex]`.
3. Display/log `index / total`, `tag`, `type`, and `area` before teleporting.
4. Attempt the teleport once.
5. Advance the cursor only after the request has been successfully issued.
6. Wrap to index zero after the last point.

Cross-world loading may recreate AutoDriver state. The implementation must verify cursor persistence. Preferred order:

1. Use a saved AutoDriver variable if it survives world changes reliably.
2. If it does not, store the cursor in a uniquely named game fact and document that save-state side effect.

### 4.3 Position resolution

Resolve `worldPath` from `pin.area`, then call `GetFastTravelPointPosition(...)`.

Use the pin type to choose the resolver mode:

- `RoadSign`: request its land waypoint.
- `Harbor`: request its harbor waypoint even when the player is not currently sailing.

This intentionally tests every pin. Harbor destinations may expose player-placement issues because some are designed for boats; these failures must be logged rather than silently filtered.

### 4.4 Local destination

If the destination world path equals the current world's depot path:

1. Cancel AutoDriver/player movement actions.
2. Require the player to be on foot for the first version, or explicitly dismount before teleporting.
3. Normalize destination rotation pitch/roll to zero.
4. Call `TeleportWithRotation(position, rotation)`.
5. Log success and selected pin metadata.

### 4.5 Cross-world destination

If the destination belongs to another world:

1. Resolve the destination position and rotation.
2. Call `ScheduleWorldChangeToPosition(worldPath, position, rotation)`.
3. If resolution fails, call `ScheduleWorldChangeToMapPin(worldPath, pin.tag)`.
4. Do not immediately issue another teleport while a world change is pending.
5. Rebuild/validate the point list after loading completes before the next key press.

### 4.6 Failure handling

- Empty list: show HUD error and do nothing.
- Unknown area/world path: log and keep the cursor on that entry for inspection, or provide an explicit skip-on-next-press rule.
- Failed position lookup: use the official map-pin fallback only for cross-world travel; for local travel, log the failure and do not brute-force teleport to the visible map-pin coordinate.
- Player in combat, scene, boat, horse, or another blocked state: first version should refuse with a clear HUD message instead of forcing state transitions.

### 4.7 Validation record

Log one line per attempt containing:

```text
index,total,tag,type,area,worldPath,local/global,positionResolved,requestIssued
```

This makes it possible to identify exactly which official pin causes a bad spawn or failed world load.

## 5. NumPad9 Design: Random XY In Current World

### 5.1 Stability strategy

Unconstrained random world XY is unsafe because distant navigation data may not be loaded and the world's rectangular coordinate envelope contains ocean, void, interiors, cliffs, and quest-only spaces.

The first implementation will use an anchor-assisted random-XY strategy:

1. Stay in the current world only.
2. Select an official current-world fast-travel waypoint as a known-safe anchor.
3. Teleport to the anchor if it is not already near the player, allowing the destination area/chunk to load.
4. Generate random XY offsets around that anchor within a configurable radius.
5. Validate the candidate against navigation and physics data.
6. Teleport only after all checks pass.

The final XY remains random, but the search starts near known playable terrain instead of an arbitrary world rectangle.

### 5.2 Candidate validation pipeline

For each candidate, up to a fixed maximum attempt count:

1. Generate random `X/Y` offset around the anchor.
2. Seed `Z` from the anchor waypoint.
3. Call `NavigationFindSafeSpot(candidate, personalSpace, searchRadius, safePosition)`.
4. Call `NavigationComputeZ(safePosition, zMin, zMax, correctedZ)`.
5. Set `safePosition.Z = correctedZ`.
6. Call `NavigationFindSafeSpot(...)` again after correcting Z.
7. Check the player's moving agent `IsPositionValid(safePosition)`.
8. Optionally use `PhysicsCorrectZ(...)` as a final ground correction/check, not as the sole source of safety.
9. Reject excessive vertical difference, water/harbor candidates where detectable, and zero/uninitialized vectors.
10. Call `TeleportWithRotation(...)` only for a fully accepted candidate.

No brute-force fallback is allowed. If all candidates fail, leave the player at the safe anchor and report failure.

### 5.3 Proposed initial parameters

- Random offset radius: `20` to `100` world units from anchor.
- Candidate attempts: `20`.
- Safe-spot personal space: approximately `1.0`.
- Safe-spot search radius: approximately `6.0`.
- Z search range: start with anchor Z `-20` to `+20`, then tune from test results.
- Destination rotation: preserve player yaw; set pitch and roll to zero.

### 5.4 Two-stage execution

If the selected anchor is far away, random XY may require a latent/timed two-stage operation:

1. Stable teleport to anchor.
2. Wait briefly for streaming/navigation data.
3. Search for a random safe candidate.
4. Perform the final local teleport.

The implementation must guard against a second key press while this operation is active.

### 5.5 Validation

- Test outdoors in each major world.
- Test near cities, forests, coastlines, mountains, and islands.
- Confirm no spawn below terrain, inside objects, underwater, or in persistent falling state.
- Confirm failure leaves the player at a known-safe location.
- Record anchor and final coordinates for every attempt.

## 6. Implementation Order

1. Add `NumPad7` god-mode toggle with health invulnerability, one-time oxygen refill, and reversible equipment durability protection.
2. Test damage, diving, repeated toggles, and world transition behavior.
3. Replace `NumPad8` binding and implement complete fast-travel enumeration plus sequential cursor/logging.
4. Test local road signs first without adding filters to the list logic.
5. Test cross-world road signs, then harbor entries and special/duplicate areas.
6. Add `NumPad9` anchor-assisted random XY using the full validation pipeline.
7. Test failure paths before increasing random offset radius.
8. Update `PROJECT.md` with confirmed runtime behavior and WitcherScript compile lessons.

## 7. Non-Goals For The First Version

- No automatic repeated teleport loop; one key press issues one operation.
- No forced teleport during scenes, combat, horse riding, sailing, or other unsafe player states.
- No arbitrary cross-world random XY.
- No brute-force teleport when navmesh validation fails.
- No blanket negative-buff immunity as part of god mode.
- No removal of the old movement experiment code until the new features are proven.

## 8. Review Decisions

The following choices should be reviewed before implementation:

1. `NumPad8` uses sequential traversal to guarantee coverage of every official point, rather than choosing a random point each press.
2. Harbor points are included and attempted even while the player is on foot, because the requirement says no filtering; they are treated as an explicit risk category in logs.
3. `NumPad9` interprets random XY as a random validated point near a randomly chosen safe anchor in the current world, not an unconstrained point anywhere in the world's rectangular bounds.
4. God mode maintains full `BCS_Air` and removes drowning instead of enabling immunity to every negative effect.

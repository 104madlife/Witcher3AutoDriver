# AutoDriver Agent Notes

## WitcherScript API ownership

- Before copying an unqualified engine call from another mod, inspect the declaring class and its inheritance chain.
- `AddTimer` and `RemoveTimer` are imported methods of `CEntity` (`engine/entity.ws`), not global functions and not methods of `IScriptable`.
- `CModAutoDriver` extends `CMod`, and `CMod` extends `IScriptable`; therefore it cannot call `AddTimer` or `RemoveTimer` directly.
- A timer callback is resolved on the entity that owns the timer. Calling `thePlayer.AddTimer(...)` does not invoke a `timer function` declared on `CModAutoDriver`.
- StoryBoardUI timer examples work because their timer-owning classes, such as `CRadishStoryBoardUi`, extend `CEntity`. Do not infer that the same calls work inside a `CMod`.
- For periodic AutoDriver work, use a real `CEntity` helper with the callback on that helper, or use an independently verified engine mechanism. Do not guess based only on method names.

## Compile-error discipline

- For every `Could not find function` error, locate the function declaration and verify receiver type, inheritance, parameters, return type, and latent behavior before editing.
- Do not move an unqualified call onto another object unless the callback/lifecycle semantics have also been verified.
- Never place a latent function call directly in a `return` statement or boolean condition. Assign its result to a local variable first, then return or branch on that variable.

## Vehicle state ownership

- `CAIStorageRiderData.sharedParams.mountStatus` is shared vehicle state and is not proof that the player is riding a horse. Boats can also expose rider/vehicle state.
- Before applying horse-only behavior such as `DismountVehicle(horse, DT_instant)`, identify a real horse through `GetHorseCurrentlyMounted()` or `GetUsedHorseComponent()`.
- Teleport preparation must not require rider data for players who are swimming, fighting, climbing, sailing, or using another vehicle.

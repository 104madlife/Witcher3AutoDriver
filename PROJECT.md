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

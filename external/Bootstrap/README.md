# Vendored Bootstrap dependency

This directory contains the complete Bootstrap runtime required by the current AutoDriver loading design:

- `game-root/mods/modBootstrap`
- `game-root/mods/modBootstrap-registry`
- `game-root/dlc/dlcBootstrap`

The payload was captured from the Bootstrap 0.5 Next-Gen installation that was used for AutoDriver's successful game compilation and runtime validation. `package.ps1` records every packaged file and SHA-256 value, and `deploy.ps1` refuses to overwrite an installed Bootstrap tree whose expected files differ.

`modBootstrap-registry` is shared integration state. On a clean installation the bundled registry is installed. When a registry already exists, deployment preserves it and adds only one `add(createAutoDriver());` line after creating a byte-for-byte backup.

Source: <https://www.nexusmods.com/witcher3/mods/2109>

The upstream Nexus permissions do not allow redistribution on other sites without the author's permission. Keep the repository private unless permission is obtained, and do not publish generated packages containing this directory.

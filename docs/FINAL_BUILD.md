# Final Build Notes

## Settings Persistence (`settings.lua`) in Packaged Builds

Current behavior in this project now writes/reads settings from per-user config paths.
Root-level `settings.lua` is only a **legacy fallback** for compatibility/migration.

## Active Paths

- **Linux**: `$XDG_CONFIG_HOME/PPUX/settings.lua` (fallback `~/.config/PPUX/settings.lua`)
- **Windows**: `%APPDATA%\\PPUX\\settings.lua`
- **macOS**: `~/Library/Application Support/PPUX/settings.lua`

This keeps behavior stable across AppImage, Windows installer/portable exe, and macOS app bundles.

## Migration/Fallback Behavior

- On startup, app tries per-user path first.
- If missing, app falls back to local root `settings.lua`.
- On next successful save, settings are written to per-user path.

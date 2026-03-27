# PPUX Itch.io Description

PPUX is a desktop NES graphics editor for working directly with ROM art data and custom project layouts.

It lets you browse CHR and ROM graphics, edit pixels, build static art and animation layouts, manage palettes, and work with ROM-backed views such as OAM animation and PPU frame windows. The goal is to make NES art iteration practical without losing control over the original game data.

PPUX supports:

- CHR Banks and ROM Banks source windows
- Static Art and Animation windows for tiles and sprites
- Global palette and ROM palette editing
- OAM animation windows
- PPU frame windows for ROM-backed screen data
- Lua project files for custom workspaces and game-specific setups

Right now, some ROM-backed windows still need to be defined manually in Lua project files, especially when they depend on ROM addresses and game-specific metadata. That part of the workflow will improve over time.

PPUX is still in active development, but it is already usable for real project work and game-specific editor setups.

Suggested screenshots for now:

- `img/readme_images/app_example.png`
- `img/readme_images/dr_mario_animation.gif`

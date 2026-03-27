# Architecture (Simple Overview)

```text
+----------------------+
|      love2d app      |
|      main.lua        |
+----------------------+
          |
          v
+----------------------+
| AppCoreController    |
+----------------------+
          |
          +------------------+------------------+------------------+------------------+
          |                  |                  |                  |                  |
          v                  v                  v                  v                  v
+------------------+ +------------------+ +------------------+ +------------------+ +------------------+
| Input Routing    | | Window Manager   | | Domain Logic     | | UI Layer         | | Persistence      |
| controllers/     | | controllers/     | | controllers/     | | user_interface/  | | controllers/     |
| input/           | | window/          | | sprite, ppu,     | | windows, modals, | | rom, app,        |
| input_support/   | |                  | | palette, chr,    | | toolbars,        | | game_art         |
|                  | |                  | | png              | | widgets          | |                  |
+------------------+ +------------------+ +------------------+ +------------------+ +------------------+


+----------------------------------------------------------------------------------------------+
| INPUT ROUTING                                                                                |
+----------------------------------------------------------------------------------------------+
| controllers/input/input.lua                                                                  |
|   - aggregates keyboard and mouse event handling                                             |
|                                                                                              |
| controllers/input/keyboard_*.lua                                                             |
| controllers/input/mouse_*.lua                                                                |
|   - extracted event behaviors (shortcuts, drag, click, wheel, overlay, chrome)               |
|                                                                                              |
| controllers/input_support/*.lua                                                              |
|   - brush, selection helpers, undo/redo, cursor manager, tile/sprite offset, etc             |
+----------------------------------------------------------------------------------------------+


+----------------------------------------------------------------------------------------------+
| WINDOW MANAGER                                                                               |
+----------------------------------------------------------------------------------------------+
| controllers/window/window_controller.lua                                                     |
|   - owns list of windows, focus, order, sorting, collapse/minimize/expand                    |
|                                                                                              |
| controllers/window/toolbar_controller.lua                                                    |
| controllers/window/window_capabilities.lua                                                   |
|   - toolbar setup and per-window-kind capability checks                                      |
+----------------------------------------------------------------------------------------------+


+----------------------------------------------------------------------------------------------+
| DOMAIN LOGIC                                                                                 |
+----------------------------------------------------------------------------------------------+
| controllers/rom/*.lua                                                                        |
|   - rom/project load, save, import, patch apply                                              |
|                                                                                              |
| controllers/game_art/*.lua                                                                   |
|   - project layout and game art composition                                                  |
|                                                                                              |
| controllers/sprite/*.lua                                                                     |
|   - sprite edit/drag/transform/import/persistence                                            |
|                                                                                              |
| controllers/ppu/*.lua                                                                        |
|   - nametable + ppu frame behaviors                                                          |
|                                                                                              |
| controllers/palette/*.lua                                                                    |
| controllers/chr/*.lua                                                                        |
| controllers/png/*.lua                                                                        |
| controllers/dev/*.lua                                                                        |
+----------------------------------------------------------------------------------------------+


+----------------------------------------------------------------------------------------------+
| UI LAYER                                                                                     |
+----------------------------------------------------------------------------------------------+
| user_interface/windows_system/*.lua                                                          |
|   - base window and specialized windows                                                      |
|                                                                                              |
| user_interface/toolbars/*.lua                                                                |
|   - header + specialized toolbars                                                            |
|                                                                                              |
| user_interface/modals/*.lua                                                                  |
|   - settings, quit confirm, new window, generic actions                                      |
|                                                                                              |
| user_interface/button.lua                                                                    |
| user_interface/panel.lua                                                                     |
| user_interface/text_field.lua                                                                |
| user_interface/taskbar.lua                                                                   |
+----------------------------------------------------------------------------------------------+


+----------------------------------------------------------------------------------------------+
| PERSISTENCE                                                                                  |
+----------------------------------------------------------------------------------------------+
| Project and ROM                                                                              |
|   - controllers/rom/rom_project_controller.lua                                               |
|   - controllers/rom/save_controller.lua                                                      |
|   - controllers/game_art/*                                                                   |
|                                                                                              |
| App settings                                                                                 |
|   - controllers/app/settings_controller.lua                                                  |
|   - utils/settings_path.lua                                                                  |
|   - conf.lua reads same settings on startup                                                  |
|                                                                                              |
| settings paths                                                                               |
|   Linux   : $XDG_CONFIG_HOME/PPUX/settings.lua or ~/.config/PPUX/settings.lua                |
|   Windows : %APPDATA%/PPUX/settings.lua                                                      |
|   macOS   : ~/Library/Application Support/PPUX/settings.lua                                  |
+----------------------------------------------------------------------------------------------+


+----------------------------------------------------------------------------------------------+
| ASSETS AND SUPPORT                                                                           |
+----------------------------------------------------------------------------------------------+
| img/*      -> icons and spritesheets                                                         |
| lib/*      -> runtime libs (example: katsudo)                                                |
| utils/*    -> shared helpers (text, table, timer, draw, settings path)                       |
| examples/* -> sample projects                                                                |
| test/*     -> test runner and unit tests                                                     |
+----------------------------------------------------------------------------------------------+


+-----------------------------------------------+
| MENTAL MODEL                                  |
+-----------------------------------------------+
| AppCoreController routes.                     |
| Controllers implement behavior.               |
| UI files render and handle                    |
| interaction surfaces.                         |
| Persistence modules own save/load concerns.   |
+-----------------------------------------------+
```

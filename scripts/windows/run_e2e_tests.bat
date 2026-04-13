@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
set "ABORT_ALL_FLAG=%TEMP%\ppux_e2e_abort_all.flag"
if exist "%ABORT_ALL_FLAG%" del /q "%ABORT_ALL_FLAG%"

set "SCENARIOS=default_action_delay modals boot_and_drag animation_playback tile_edit_roundtrip brush_paint_tools new_window_variants palette_shader_preview static_sprite_ops undo_redo_events palette_edit_roundtrip save_reload_persistence submenu_positions context_menus_and_submenus window_resize_and_hover_priority modal_navigation_keyboard_only text_field_variants clipboard_matrix ppu_toolbar_ranges_setup ppu_toolbar_pattern_ranges ppu_toolbar_sprite_and_mode_controls"

set /a pass_count=0
set /a fail_count=0

for %%S in (%SCENARIOS%) do (
  echo Running visual E2E scenario: %%S
  call "%SCRIPT_DIR%run_e2e_demo.bat" "%%S"
  set "status=!errorlevel!"

  if exist "%ABORT_ALL_FLAG%" (
    echo ABORTED ALL VISUAL E2E SCENARIOS
    del /q "%ABORT_ALL_FLAG%"
    exit /b 130
  )

  if "!status!"=="0" (
    echo PASS: %%S
    set /a pass_count+=1
  ) else (
    echo FAIL: %%S ^(exit !status!^)
    set /a fail_count+=1
  )
)

echo.
echo Visual E2E summary: !pass_count! passed, !fail_count! failed

if !fail_count! gtr 0 exit /b 1
exit /b 0

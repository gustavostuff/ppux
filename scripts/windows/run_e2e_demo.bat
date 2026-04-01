@echo off
setlocal EnableExtensions

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..\..") do set "ROOT_DIR=%%~fI"

where love >nul 2>nul
if errorlevel 1 (
  echo Error: 'love' command not found. Please install LÖVE2D first.
  exit /b 1
)

set "SCENARIO=%~1"
if "%SCENARIO%"=="" set "SCENARIO=modals"
set "SPEED=%~2"

pushd "%ROOT_DIR%" >nul
if "%SPEED%"=="" (
  love . --e2e "%SCENARIO%"
) else (
  love . --e2e "%SCENARIO%" --e2e-speed "%SPEED%"
)
set "STATUS=%ERRORLEVEL%"
popd >nul

exit /b %STATUS%

@echo off
setlocal EnableExtensions

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..\..") do set "ROOT_DIR=%%~fI"

where love >nul 2>nul
if errorlevel 1 (
  echo Error: 'love' command not found. Please install LÖVE2D first.
  echo Visit https://love2d.org/ for installation instructions.
  exit /b 1
)

pushd "%ROOT_DIR%\test" >nul
if "%~1"=="" (
  love .
) else (
  love . -- "%~1"
)
set "STATUS=%ERRORLEVEL%"
popd >nul

exit /b %STATUS%

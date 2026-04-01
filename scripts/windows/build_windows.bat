@echo off
setlocal EnableExtensions

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..\..") do set "ROOT_DIR=%%~fI"

if not defined APP_NAME set "APP_NAME=PPUX"
if not defined BUILD_DIR set "BUILD_DIR=%ROOT_DIR%\build"
if not defined APP_VERSION if exist "%ROOT_DIR%\version.txt" set /p APP_VERSION=<"%ROOT_DIR%\version.txt"
if defined APP_VERSION (
  set "VERSION_SUFFIX=-%APP_VERSION%"
) else (
  set "VERSION_SUFFIX="
)
if not defined BASE_RUNTIME_DIR set "BASE_RUNTIME_DIR=%ROOT_DIR%\base-love2d-images"
if not defined WIN_RUNTIME_URL set "WIN_RUNTIME_URL=https://github.com/love2d/love/releases/download/11.5/love-11.5-win64.zip"
if not defined WIN_RUNTIME_ZIP set "WIN_RUNTIME_ZIP=%BASE_RUNTIME_DIR%\love-11.5-win64.zip"
if not defined WIN_RUNTIME_DIR set "WIN_RUNTIME_DIR=%ROOT_DIR%\base-love2d-images\love-11.5-win64"
if not defined PACKAGE_STAGE_DIR set "PACKAGE_STAGE_DIR=%TEMP%\ppux-win64-%RANDOM%%RANDOM%\%APP_NAME%-win64"
if not defined OUT_ZIP set "OUT_ZIP=%BUILD_DIR%\%APP_NAME%%VERSION_SUFFIX%-win64.zip"

set "LOVE_ARCHIVE=%BUILD_DIR%\%APP_NAME%.love"
set "LOVE_ARCHIVE_ZIP=%BUILD_DIR%\%APP_NAME%.zip"
set "STAGE_DIR=%BUILD_DIR%\windows-stage\%APP_NAME%"

where powershell >nul 2>nul
if errorlevel 1 (
  echo Missing PowerShell. This script requires Windows PowerShell to create the .love archive.
  exit /b 1
)

if defined APP_VERSION (
  powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ErrorActionPreference = 'Stop';" ^
    "$readme = Join-Path $env:ROOT_DIR 'README.md';" ^
    "if (Test-Path -LiteralPath $readme) {" ^
    "  $content = Get-Content -LiteralPath $readme -Raw;" ^
    "  $content = [regex]::Replace($content, '(?m)^Version: .*$','Version: ' + $env:APP_VERSION);" ^
    "  $content = [regex]::Replace($content, '(?m)^Beta v.*$','Version: ' + $env:APP_VERSION);" ^
    "  Set-Content -LiteralPath $readme -Value $content -NoNewline;" ^
    "}"
  if errorlevel 1 exit /b 1
)

if not exist "%BASE_RUNTIME_DIR%" mkdir "%BASE_RUNTIME_DIR%"

if not exist "%WIN_RUNTIME_DIR%\love.exe" (
  if not exist "%WIN_RUNTIME_ZIP%" (
    echo Downloading Windows runtime: %WIN_RUNTIME_URL%
    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
      "$ErrorActionPreference = 'Stop';" ^
      "Invoke-WebRequest -Uri $env:WIN_RUNTIME_URL -OutFile $env:WIN_RUNTIME_ZIP;"
    if errorlevel 1 exit /b 1
  )

  echo Extracting Windows runtime to: %BASE_RUNTIME_DIR%
  powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ErrorActionPreference = 'Stop';" ^
    "Expand-Archive -LiteralPath $env:WIN_RUNTIME_ZIP -DestinationPath $env:BASE_RUNTIME_DIR -Force;"
  if errorlevel 1 exit /b 1
)

if not exist "%WIN_RUNTIME_DIR%\love.exe" (
  echo Windows runtime extraction did not produce %WIN_RUNTIME_DIR%\love.exe
  exit /b 1
)

if not exist "%BUILD_DIR%" mkdir "%BUILD_DIR%"

set "ROOT_DIR_PS=%ROOT_DIR%"
set "STAGE_DIR_PS=%STAGE_DIR%"
set "LOVE_ARCHIVE_PS=%LOVE_ARCHIVE%"
set "LOVE_ARCHIVE_ZIP_PS=%LOVE_ARCHIVE_ZIP%"

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference = 'Stop';" ^
  "$root = [System.IO.Path]::GetFullPath($env:ROOT_DIR_PS);" ^
  "$stage = [System.IO.Path]::GetFullPath($env:STAGE_DIR_PS);" ^
  "$archive = [System.IO.Path]::GetFullPath($env:LOVE_ARCHIVE_PS);" ^
  "$archiveZip = [System.IO.Path]::GetFullPath($env:LOVE_ARCHIVE_ZIP_PS);" ^
  "$excludeDirs = @('.git', 'build', 'base-love2d-images', 'docs', 'examples', 'scripts', 'test', 'tmp', 'bkps');" ^
  "$excludeExts = @('.sh', '.love', '.appimage', '.bat', '.cmd');" ^
  "if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force };" ^
  "New-Item -ItemType Directory -Path $stage -Force | Out-Null;" ^
  "$files = Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object {" ^
  "  $full = [System.IO.Path]::GetFullPath($_.FullName);" ^
  "  $rel = $full.Substring($root.Length).TrimStart('\');" ^
  "  if ([string]::IsNullOrWhiteSpace($rel)) { return $false }" ^
  "  $parts = $rel -split '\\\\';" ^
  "  if ($parts.Length -gt 1) {" ^
  "    foreach ($part in $parts[0..($parts.Length - 2)]) {" ^
  "      if ($excludeDirs -contains $part) { return $false }" ^
  "    }" ^
  "  }" ^
  "  if ($excludeExts -contains $_.Extension.ToLowerInvariant()) { return $false }" ^
  "  return $true" ^
  "};" ^
  "foreach ($file in $files) {" ^
  "  $full = [System.IO.Path]::GetFullPath($file.FullName);" ^
  "  $rel = $full.Substring($root.Length).TrimStart('\');" ^
  "  $dest = Join-Path $stage $rel;" ^
  "  $destDir = Split-Path -Parent $dest;" ^
  "  if (-not (Test-Path -LiteralPath $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }" ^
  "  Copy-Item -LiteralPath $full -Destination $dest -Force;" ^
  "};" ^
  "if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -Force };" ^
  "if (Test-Path -LiteralPath $archiveZip) { Remove-Item -LiteralPath $archiveZip -Force };" ^
  "Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $archiveZip -CompressionLevel Optimal -Force;" ^
  "Move-Item -LiteralPath $archiveZip -Destination $archive -Force;"
if errorlevel 1 exit /b 1

if exist "%PACKAGE_STAGE_DIR%" rmdir /s /q "%PACKAGE_STAGE_DIR%"
mkdir "%PACKAGE_STAGE_DIR%"
if not exist "%BUILD_DIR%" mkdir "%BUILD_DIR%"

copy /b "%WIN_RUNTIME_DIR%\love.exe"+"%LOVE_ARCHIVE%" "%PACKAGE_STAGE_DIR%\%APP_NAME%.exe" >nul
if errorlevel 1 (
  echo Failed to fuse love.exe with %LOVE_ARCHIVE%.
  exit /b 1
)

for %%F in (
  OpenAL32.dll
  SDL2.dll
  love.dll
  lua51.dll
  mpg123.dll
  msvcp120.dll
  msvcr120.dll
  license.txt
) do (
  if exist "%WIN_RUNTIME_DIR%\%%F" (
    copy "%WIN_RUNTIME_DIR%\%%F" "%PACKAGE_STAGE_DIR%\" >nul
  )
)

if exist "%WIN_RUNTIME_DIR%\game.ico" (
  copy "%WIN_RUNTIME_DIR%\game.ico" "%PACKAGE_STAGE_DIR%\" >nul
)

set "PACKAGE_STAGE_DIR_PS=%PACKAGE_STAGE_DIR%"
set "OUT_ZIP_PS=%OUT_ZIP%"
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference = 'Stop';" ^
  "$outDir = [System.IO.Path]::GetFullPath($env:PACKAGE_STAGE_DIR_PS);" ^
  "$outZip = [System.IO.Path]::GetFullPath($env:OUT_ZIP_PS);" ^
  "if (Test-Path -LiteralPath $outZip) { Remove-Item -LiteralPath $outZip -Force };" ^
  "Compress-Archive -Path $outDir -DestinationPath $outZip -CompressionLevel Optimal -Force;"
if errorlevel 1 exit /b 1

if exist "%PACKAGE_STAGE_DIR%" rmdir /s /q "%PACKAGE_STAGE_DIR%"
if exist "%STAGE_DIR%" rmdir /s /q "%STAGE_DIR%"

echo Done: %OUT_ZIP%

endlocal

@echo off
setlocal EnableExtensions

set "ROOT_DIR=%~dp0"
call "%ROOT_DIR%scripts\windows\run_unit_tests.bat" %*
exit /b %ERRORLEVEL%

@echo off
setlocal EnableExtensions

set "ROOT_DIR=%~dp0"
call "%ROOT_DIR%scripts\windows\run_e2e_tests.bat" %*
exit /b %ERRORLEVEL%

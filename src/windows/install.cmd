@echo off
rem install.cmd: runs install.ps1 (no execution-policy change needed). Options are passed on.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
exit /b %ERRORLEVEL%

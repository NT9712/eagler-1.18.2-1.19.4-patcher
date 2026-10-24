@echo off
rem MakeOfflineDownload.cmd: runs MakeOfflineDownload.ps1 (no execution-policy change needed). Options are passed on.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0MakeOfflineDownload.ps1" %*
exit /b %ERRORLEVEL%

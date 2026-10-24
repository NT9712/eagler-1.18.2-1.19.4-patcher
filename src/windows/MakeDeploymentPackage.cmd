@echo off
rem MakeDeploymentPackage.cmd: runs MakeDeploymentPackage.ps1 (no execution-policy change needed). Options are passed on.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0MakeDeploymentPackage.ps1" %*
exit /b %ERRORLEVEL%

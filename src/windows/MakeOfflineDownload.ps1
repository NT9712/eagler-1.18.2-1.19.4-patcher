# MakeOfflineDownload.ps1: Windows entry point for MakeOfflineDownload.sh (runs it in Git Bash; same options, e.g. --js / --wasm).
# Run: MakeOfflineDownload.cmd [options]   or   powershell -ExecutionPolicy Bypass -File MakeOfflineDownload.ps1 [options]
Set-Location -LiteralPath $PSScriptRoot
. "$PSScriptRoot\patcher\lib\win.ps1"
Assert-Windows
if (-not (Test-Path .patcher-installed)) { Die 'Run install.cmd (or install.ps1) first.' }
Install-Deps -Yes
Invoke-BashScript 'MakeOfflineDownload.sh' $args

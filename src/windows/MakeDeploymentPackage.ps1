# MakeDeploymentPackage.ps1: Windows entry point for MakeDeploymentPackage.sh (runs it in Git Bash; same options, e.g. --js / --wasm).
# Run: MakeDeploymentPackage.cmd [options]   or   powershell -ExecutionPolicy Bypass -File MakeDeploymentPackage.ps1 [options]
Set-Location -LiteralPath $PSScriptRoot
. "$PSScriptRoot\patcher\lib\win.ps1"
Assert-Windows
if (-not (Test-Path .patcher-installed)) { Die 'Run install.cmd (or install.ps1) first.' }
Install-Deps -Yes
Invoke-BashScript 'MakeDeploymentPackage.sh' $args

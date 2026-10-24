# install.ps1: Windows entry point for install.sh (Minecraft @VER@ browser port).
# Checks RAM/disk, installs Git for Windows (bash), Python 3 and ffmpeg with winget (or Chocolatey / Scoop) when
# missing, then runs ./install.sh in Git Bash. JDK 17, Gradle and Node are downloaded into tools/ by install.sh, exactly
# like on Linux and macOS. Options are passed on to install.sh: --yes --no-decompile --no-sounds --client-url=URL
# Run: install.cmd [options]   or   powershell -ExecutionPolicy Bypass -File install.ps1 [options]
Set-Location -LiteralPath $PSScriptRoot
. "$PSScriptRoot\patcher\lib\win.ps1"
Say 'Minecraft @VER@ browser port: Windows setup'
Assert-Windows
Test-Resources
Install-Deps -Yes:([bool]($args -contains '--yes' -or $args -contains '-y' -or $env:CI))
Invoke-BashScript 'install.sh' $args

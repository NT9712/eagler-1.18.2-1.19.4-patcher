# Shared helpers for the Windows entry points (install.ps1, MakeDeploymentPackage.ps1, MakeOfflineDownload.ps1).
# Windows only prepares the machine (RAM/disk check, Git for Windows, Python 3, ffmpeg) and then runs the same bash
# scripts as Linux/macOS through Git Bash, so the build logic lives in one place.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

$MinRamMB  = if ($env:MIN_RAM_MB)  { [int]$env:MIN_RAM_MB }  else { 7400 }   # same thresholds as patcher/lib/common.sh
$MinDiskMB = if ($env:MIN_DISK_MB) { [int]$env:MIN_DISK_MB } else { 9000 }

function Say($m)  { Write-Host "`n== $m ==" -ForegroundColor White }
function Step($m) { Write-Host "-> $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "   ok $m" -ForegroundColor Green }
function Notice-Exit($m) { Write-Host "`nNOTICE: $m`n`nNothing was changed. Exiting." -ForegroundColor Yellow; exit 2 }
function Die($m) { Write-Host "`nERROR: $m" -ForegroundColor Red; exit 1 }

function Assert-Windows {
  if ($env:OS -ne 'Windows_NT') { Die 'This script is for Windows. On Linux/macOS run the .sh scripts.' }
  if (-not [Environment]::Is64BitOperatingSystem) { Notice-Exit 'Needs 64-bit Windows (x64 or arm64).' }
}

function Test-Resources {
  Step 'Checking this machine'
  $ram = [int]((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1MB)
  $root = [IO.Path]::GetPathRoot((Get-Location).ProviderPath)
  $disk = [int]((New-Object IO.DriveInfo $root).AvailableFreeSpace / 1MB)
  if ($ram -lt $MinRamMB) { Notice-Exit "This machine has $ram MB of RAM. Building the port needs about 8 GB (min $MinRamMB MB): TeaVM and the decompiler each need ~5 GB of Java heap." }
  if ($disk -lt $MinDiskMB) { Notice-Exit "Only $disk MB free on $root. Needs about $([int]($MinDiskMB/1000)) GB free." }
  Ok "RAM $ram MB, free disk $disk MB on $root, $env:PROCESSOR_ARCHITECTURE, $env:NUMBER_OF_PROCESSORS CPUs"
}

# Pick up PATH changes made by installers without opening a new window.
function Update-SessionPath {
  $parts = @([Environment]::GetEnvironmentVariable('Path', 'Machine'), [Environment]::GetEnvironmentVariable('Path', 'User'), $env:Path) -join ';'
  $seen = @{}; $out = @()
  foreach ($p in $parts -split ';') { if ($p -and -not $seen.ContainsKey($p.ToLower())) { $seen[$p.ToLower()] = 1; $out += $p } }
  $env:Path = $out -join ';'
}

function Find-GitBash {
  $c = @()
  $git = Get-Command git -ErrorAction SilentlyContinue
  if ($git) {
    $d = Split-Path $git.Source
    $c += (Join-Path $d '..\bin\bash.exe'), (Join-Path $d '..\..\bin\bash.exe')
  }
  foreach ($k in 'HKLM:\SOFTWARE\GitForWindows', 'HKCU:\SOFTWARE\GitForWindows') {
    $ip = (Get-ItemProperty $k -ErrorAction SilentlyContinue).InstallPath
    if ($ip) { $c += (Join-Path $ip 'bin\bash.exe') }
  }
  $c += "$env:ProgramFiles\Git\bin\bash.exe", "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe", "$env:USERPROFILE\scoop\apps\git\current\bin\bash.exe"
  foreach ($p in $c) { if ($p -and (Test-Path $p)) { return (Resolve-Path $p).ProviderPath } }
  return $null
}

# A real Python 3.8+ (not the Microsoft Store "python" stub); returns python.exe's full path.
function Find-Python {
  $ErrorActionPreference = 'Continue'
  $tries = @()
  if (Get-Command py -ErrorAction SilentlyContinue) { $tries += , @('py', '-3') }
  foreach ($n in 'python', 'python3') {
    foreach ($cmd in @(Get-Command $n -All -CommandType Application -ErrorAction SilentlyContinue)) {
      if ($cmd.Source -notmatch '\\WindowsApps\\') { $tries += , @($cmd.Source) }
    }
  }
  foreach ($t in $tries) {
    try {
      $exe = $t[0]; $a = @($t | Select-Object -Skip 1) + @('-c', 'import sys; print(sys.executable if sys.version_info >= (3, 8) else "")')
      $out = & $exe @a 2>$null
      if ($LASTEXITCODE -eq 0 -and $out -and (Test-Path "$out".Trim())) { return "$out".Trim() }
    } catch {}
  }
  return $null
}

function Test-Tool($name) {
  switch ($name) {
    'git'    { return [bool](Find-GitBash) }
    'python' { return [bool](Find-Python) }
    default  { return [bool](Get-Command $name -ErrorAction SilentlyContinue) }
  }
}

# winget first, then Chocolatey, then Scoop.
$Pkgs = @{
  git    = @{ winget = 'Git.Git';              choco = 'git';        scoop = 'git' }
  python = @{ winget = 'Python.Python.3.12';   choco = 'python312';  scoop = 'python' }
  ffmpeg = @{ winget = 'Gyan.FFmpeg';          choco = 'ffmpeg';     scoop = 'ffmpeg' }
}
function Install-Tool($name) {
  $p = $Pkgs[$name]
  $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
      Step "Installing $name with winget ($($p.winget))"
      & winget install --id $p.winget -e --source winget --accept-source-agreements --accept-package-agreements --silent | Out-Host
      Update-SessionPath; if (Test-Tool $name) { return $true }
    }
    if (Get-Command choco -ErrorAction SilentlyContinue) {
      Step "Installing $name with Chocolatey ($($p.choco))"
      & choco install -y --no-progress $p.choco | Out-Host
      Update-SessionPath
      $chocoBin = Join-Path $env:ProgramData 'chocolatey\bin'; if (Test-Path $chocoBin) { $env:Path = "$chocoBin;$env:Path" }
      if (Test-Tool $name) { return $true }
    }
    if (Get-Command scoop -ErrorAction SilentlyContinue) {
      Step "Installing $name with Scoop ($($p.scoop))"
      & scoop install $p.scoop | Out-Host
      Update-SessionPath; if (Test-Tool $name) { return $true }
    }
  } finally { $ErrorActionPreference = $eap }
  return $false
}

function Install-Deps([switch]$Yes) {
  Step 'Checking dependencies (Git for Windows, Python 3, ffmpeg)'
  Update-SessionPath
  $miss = @('git', 'python', 'ffmpeg') | Where-Object { -not (Test-Tool $_) }
  if ($miss) {
    if (-not (Get-Command winget, choco, scoop -ErrorAction SilentlyContinue)) {
      Notice-Exit "Missing: $($miss -join ', '). No winget, Chocolatey or Scoop found to install them. Install Git for Windows, Python 3 and ffmpeg yourself (or get winget: 'App Installer' from the Microsoft Store) and rerun."
    }
    if (-not $Yes -and [Environment]::UserInteractive -and -not [Console]::IsInputRedirected) {
      $a = Read-Host "Install missing tools: $($miss -join ', ') ? [Y/n]"
      if ($a -match '^[nN]') { Notice-Exit "Missing dependencies: $($miss -join ', ')" }
    }
    foreach ($m in $miss) { if (-not (Install-Tool $m)) { Die "Could not install $m. Install it yourself and rerun." } }
  }
  $script:GitBash = Find-GitBash
  $script:Python = Find-Python
  $env:MC_PYTHON = $script:Python
  $ff = (Get-Command ffmpeg).Source
  Ok "Git Bash $script:GitBash, Python $script:Python, ffmpeg $ff"
  # Long paths help the deep decompiled/ and Gradle trees; only possible as admin, harmless if it fails.
  try {
    $k = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'
    if ((Get-ItemProperty $k -ErrorAction SilentlyContinue).LongPathsEnabled -ne 1) {
      $id = [Security.Principal.WindowsIdentity]::GetCurrent()
      if ((New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Set-ItemProperty $k LongPathsEnabled 1 -Type DWord
      }
    }
  } catch {}
}

# Runs one of the workspace's bash scripts in Git Bash and exits with its status.
function Invoke-BashScript($script, [string[]]$Arguments) {
  if (-not $script:GitBash) { $script:GitBash = Find-GitBash }
  if (-not $script:GitBash) { Die 'Git Bash not found. Run install.cmd (or install.ps1) first.' }
  if (-not $env:MC_PYTHON) { $env:MC_PYTHON = Find-Python }
  $env:CHERE_INVOKING = '1'; $env:MSYSTEM = 'MINGW64'
  $ErrorActionPreference = 'Continue'   # Windows PowerShell 5.1 would otherwise turn bash's stderr into errors
  & $script:GitBash "./$script" @Arguments
  exit $LASTEXITCODE
}

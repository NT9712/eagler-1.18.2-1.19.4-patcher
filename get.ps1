# One-liner installer for the Minecraft browser-port patcher on Windows (PowerShell 5.1+ or 7).
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/NT9712/eagler-1.18.2-1.19.4-patcher/main/get.ps1))) 1.19.4
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/NT9712/eagler-1.18.2-1.19.4-patcher/main/get.ps1))) 1.18.2
#   irm https://raw.githubusercontent.com/NT9712/eagler-1.18.2-1.19.4-patcher/main/get.ps1 | iex      (asks for the version)
# Downloads the patcher zip from this repo's latest release into .\mc-<version>-web and runs its install.ps1, which
# installs Git for Windows, Python 3 and ffmpeg if missing (winget, else choco / scoop) and runs install.sh in Git Bash.
# Extra arguments are passed on (e.g. --yes --no-decompile). $env:MC_DIR picks another folder, $env:MC_VERSION the
# version when piped into iex, $env:MC_NO_INSTALL=1 only unpacks.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
$Repo = 'NT9712/eagler-1.18.2-1.19.4-patcher'
$Rest = @($args)
$Ver = $null
if ($Rest.Count -gt 0 -and $Rest[0] -notlike '-*') { $Ver = $Rest[0]; $Rest = @($Rest | Select-Object -Skip 1) }
if (-not $Ver) { $Ver = $env:MC_VERSION }
if (-not $Ver) {
  try { if ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected) { $Ver = Read-Host 'Minecraft version to set up (1.18.2 or 1.19.4) [1.19.4]' } } catch {}
  if (-not $Ver) { $Ver = '1.19.4' }
}
if ($Ver -notin '1.18.2', '1.19.4') { Write-Host "Unknown version '$Ver' (use 1.18.2 or 1.19.4)" -ForegroundColor Red; return }
$Dir = if ($env:MC_DIR) { $env:MC_DIR } else { Join-Path (Get-Location).ProviderPath "mc-$Ver-web" }
$Tmp = Join-Path ([IO.Path]::GetTempPath()) ("mcpatch-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $Tmp | Out-Null
try {
  Write-Host "-> downloading the $Ver patcher" -ForegroundColor Cyan
  $Url = "https://github.com/$Repo/releases/latest/download/mc-$Ver-web-patcher.zip"
  for ($i = 1; ; $i++) {
    try { Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile "$Tmp\p.zip"; break }
    catch { if ($i -ge 3) { throw }; Start-Sleep -Seconds 3 }
  }
  Expand-Archive -LiteralPath "$Tmp\p.zip" -DestinationPath $Tmp -Force
  New-Item -ItemType Directory -Force $Dir | Out-Null
  Copy-Item -Path "$Tmp\mc-$Ver-web\*" -Destination $Dir -Recurse -Force
} finally { Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue }
Write-Host "-> patcher unpacked in $Dir" -ForegroundColor Cyan
if ($env:MC_NO_INSTALL -eq '1') { return }
$ps = (Get-Process -Id $PID).Path
if (-not $ps -or $ps -notmatch 'pwsh|powershell') { $ps = 'powershell' }
$inst = Join-Path $Dir 'install.ps1'
& $ps -NoProfile -ExecutionPolicy Bypass -File $inst @Rest
if ($LASTEXITCODE) { Write-Host "install.ps1 exited with $LASTEXITCODE" -ForegroundColor Yellow }

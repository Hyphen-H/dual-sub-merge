#Requires -Version 5.1
<#
.SYNOPSIS
  dual-sub-merge desktop release build (fast path: skip pub get when possible)

.USAGE
  .\build_desktop.ps1
  .\build_desktop.ps1 -PubGet
  .\build_desktop.ps1 -NoLaunch
  .\build_desktop.ps1 -Open
  .\build_desktop.ps1 -Platform windows
  .\build_desktop.ps1 -VerboseFlutter
#>
param(
  [ValidateSet('windows', 'macos', 'linux')]
  [string]$Platform = 'windows',
  [switch]$Open,
  [switch]$NoLaunch,
  [switch]$VerboseFlutter,
  [switch]$PubGet
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $Root

function Find-Flutter {
  $cmd = Get-Command flutter -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }

  $candidates = @(
    "$env:USERPROFILE\scoop\apps\flutter\current\bin\flutter.bat",
    "$env:USERPROFILE\scoop\shims\flutter.bat",
    "$env:LOCALAPPDATA\flutter\bin\flutter.bat",
    "$env:USERPROFILE\flutter\bin\flutter.bat",
    "C:\flutter\bin\flutter.bat",
    "C:\src\flutter\bin\flutter.bat"
  )
  foreach ($c in $candidates) {
    if (Test-Path -LiteralPath $c) { return $c }
  }
  return $null
}

function Test-PubUpToDate {
  $pkg = Join-Path $Root '.dart_tool\package_config.json'
  if (-not (Test-Path -LiteralPath $pkg)) { return $false }

  $pkgTime = (Get-Item -LiteralPath $pkg).LastWriteTimeUtc
  foreach ($name in @('pubspec.yaml', 'pubspec.lock')) {
    $f = Join-Path $Root $name
    if (-not (Test-Path -LiteralPath $f)) { continue }
    if ((Get-Item -LiteralPath $f).LastWriteTimeUtc -gt $pkgTime) {
      return $false
    }
  }
  return $true
}

function Test-FlutterNoiseLine([string]$line) {
  $noise = @(
    'have newer versions incompatible with dependency constraints',
    'Try `flutter pub outdated`',
    "Try 'flutter pub outdated'",
    'Resolving dependencies...',
    'Downloading packages...',
    'Got dependencies!'
  )
  foreach ($n in $noise) {
    if ($line.Contains($n)) { return $true }
  }
  if ($line -match '^\s+\S+\s+\d+\.\d+.*available\)\s*$') { return $true }
  return $false
}

function Invoke-Flutter {
  param(
    [Parameter(Mandatory = $true)][string[]]$FlutterArgs,
    [switch]$QuietPubNoise
  )

  $prevCi = $env:CI
  $prevAna = $env:FLUTTER_SUPPRESS_ANALYTICS
  $env:CI = 'true'
  $env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
  try {
    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & $script:flutter @FlutterArgs 2>&1 | ForEach-Object {
      $line = "$_"
      if ($QuietPubNoise -and (Test-FlutterNoiseLine $line)) { return }
      if (-not [string]::IsNullOrWhiteSpace($line)) { Write-Host $line }
    }
    $code = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 0 }
    $ErrorActionPreference = $oldEap
  } finally {
    if ($null -eq $prevCi) { Remove-Item Env:CI -ErrorAction SilentlyContinue } else { $env:CI = $prevCi }
    if ($null -eq $prevAna) { Remove-Item Env:FLUTTER_SUPPRESS_ANALYTICS -ErrorAction SilentlyContinue } else { $env:FLUTTER_SUPPRESS_ANALYTICS = $prevAna }
  }

  if ($code -ne 0) {
    Write-Host "flutter failed (exit $code)" -ForegroundColor Red
    exit $code
  }
}

$flutter = Find-Flutter
if (-not $flutter) {
  Write-Host "Flutter not found. Install Flutter or: scoop install extras/flutter" -ForegroundColor Red
  exit 1
}

$flutterDir = Split-Path -Parent $flutter
if ($env:Path -notlike "*$flutterDir*") {
  $env:Path = "$flutterDir;$env:USERPROFILE\scoop\shims;$env:Path"
}

$env:CI = 'true'
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'

Write-Host "dual-sub-merge build ($Platform)" -ForegroundColor Green

$needPub = $PubGet -or -not (Test-PubUpToDate)
if ($needPub) {
  Write-Host "==> flutter pub get" -ForegroundColor Cyan
  Invoke-Flutter -FlutterArgs @('pub', 'get') -QuietPubNoise
} else {
  Write-Host "skip pub get (package_config up to date; use -PubGet to force)" -ForegroundColor DarkGray
}

$buildArgs = @('build', $Platform, '--release', '--no-pub')
if ($VerboseFlutter) { $buildArgs += '-v' }

Write-Host "==> flutter $($buildArgs -join ' ')" -ForegroundColor Cyan
Invoke-Flutter -FlutterArgs $buildArgs -QuietPubNoise

$outPath = switch ($Platform) {
  'windows' { Join-Path $Root 'build\windows\x64\runner\Release\dual_sub_merge.exe' }
  'macos'   { Join-Path $Root 'build\macos\Build\Products\Release\dual_sub_merge.app' }
  'linux'   { Join-Path $Root 'build\linux\x64\release\bundle\dual_sub_merge' }
}

Write-Host ""
Write-Host "Build OK" -ForegroundColor Green
if (-not (Test-Path -LiteralPath $outPath)) {
  Write-Host "  Default output path not found; check build/." -ForegroundColor Yellow
  exit 0
}

Write-Host "  exe: $outPath" -ForegroundColor Green
$dir = Split-Path -Parent $outPath
Write-Host "  dir: $dir"

if ($Open) {
  if ($IsWindows -or $env:OS -match 'Windows') {
    Start-Process explorer.exe -ArgumentList $dir
  } else {
    Start-Process $dir
  }
}

if (-not $NoLaunch) {
  Write-Host ""
  if ($Platform -eq 'windows') {
    Write-Host "Press any key to launch dual_sub_merge.exe ..." -ForegroundColor Yellow
  } else {
    Write-Host "Press any key to launch ..." -ForegroundColor Yellow
  }

  try {
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
  } catch {
    Read-Host "Press Enter to launch"
  }

  Write-Host "Launching..." -ForegroundColor Cyan
  switch ($Platform) {
    'windows' { Start-Process -FilePath $outPath -WorkingDirectory $dir }
    'macos'   { Start-Process 'open' -ArgumentList $outPath }
    'linux'   { Start-Process -FilePath $outPath -WorkingDirectory $dir }
  }
}

exit 0

#Requires -Version 5.1
<#
.SYNOPSIS
  dual-sub-merge 桌面端一键构建（Windows / 可选 macOS·Linux）

.USAGE
  .\build_desktop.ps1
  .\build_desktop.ps1 -SkipTests
  .\build_desktop.ps1 -NoLaunch          # 成功后不提示启动
  .\build_desktop.ps1 -Open              # 成功后打开输出目录
  .\build_desktop.ps1 -Platform windows
#>
param(
  [ValidateSet('windows', 'macos', 'linux')]
  [string]$Platform = 'windows',
  [switch]$SkipTests,
  [switch]$Open,
  [switch]$NoLaunch,
  [switch]$VerboseFlutter
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $Root

function Write-Step([string]$msg) {
  Write-Host ""
  Write-Host "==> $msg" -ForegroundColor Cyan
}

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

function Invoke-FlutterQuiet {
  param([Parameter(Mandatory = $true)][string[]]$FlutterArgs)

  # Hide recurring "N packages have newer versions..." tips (SDK-pinned transitive deps).
  $noise = @(
    'have newer versions incompatible with dependency constraints',
    'Try `flutter pub outdated`',
    'Try ''flutter pub outdated'''
  )

  & $script:flutter @FlutterArgs 2>&1 | ForEach-Object {
    $line = "$_"
    $skip = $false
    foreach ($n in $noise) {
      if ($line -like "*$n*") { $skip = $true; break }
    }
    if (-not $skip) { Write-Host $line }
  }

  if ($null -eq $LASTEXITCODE) { return }
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

$flutter = Find-Flutter
if (-not $flutter) {
  Write-Host "未找到 flutter。请先安装 Flutter 并加入 PATH，或使用 scoop install extras/flutter" -ForegroundColor Red
  exit 1
}

$flutterDir = Split-Path -Parent $flutter
if ($env:Path -notlike "*$flutterDir*") {
  $env:Path = "$flutterDir;$env:USERPROFILE\scoop\shims;$env:Path"
}

Write-Host "dual-sub-merge 桌面构建" -ForegroundColor Green
Write-Host "  Flutter : $flutter"
Write-Host "  平台    : $Platform"
Write-Host "  目录    : $Root"

Write-Step "flutter --version"
Invoke-FlutterQuiet -FlutterArgs @('--version')

Write-Step "flutter pub get"
Invoke-FlutterQuiet -FlutterArgs @('pub', 'get')

if (-not $SkipTests) {
  Write-Step "flutter test"
  Invoke-FlutterQuiet -FlutterArgs @('test')
} else {
  Write-Host "已跳过测试 (-SkipTests)" -ForegroundColor Yellow
}

Write-Step "flutter analyze"
Invoke-FlutterQuiet -FlutterArgs @('analyze')

$buildArgs = @('build', $Platform, '--release')
if ($VerboseFlutter) { $buildArgs += '-v' }

Write-Step ("flutter " + ($buildArgs -join ' '))
Invoke-FlutterQuiet -FlutterArgs $buildArgs

$outPath = switch ($Platform) {
  'windows' { Join-Path $Root 'build\windows\x64\runner\Release\dual_sub_merge.exe' }
  'macos'   { Join-Path $Root 'build\macos\Build\Products\Release\dual_sub_merge.app' }
  'linux'   { Join-Path $Root 'build\linux\x64\release\bundle\dual_sub_merge' }
}

Write-Host ""
Write-Host "构建成功" -ForegroundColor Green
if (-not (Test-Path -LiteralPath $outPath)) {
  Write-Host "  未定位到默认产物路径，请检查 build/ 目录。" -ForegroundColor Yellow
  exit 0
}

Write-Host "  输出: $outPath" -ForegroundColor Green
$dir = Split-Path -Parent $outPath
Write-Host "  目录: $dir"

if ($Open) {
  if ($IsWindows -or $env:OS -match 'Windows') {
    Start-Process explorer.exe -ArgumentList $dir
  } else {
    Start-Process $dir
  }
}

# Default: any key launches the app (Windows exe / macOS open / linux exec)
if (-not $NoLaunch) {
  Write-Host ""
  if ($Platform -eq 'windows') {
    Write-Host "按任意键启动 dual_sub_merge.exe ..." -ForegroundColor Yellow
  } else {
    Write-Host "按任意键启动应用 ..." -ForegroundColor Yellow
  }

  try {
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
  } catch {
    # Non-interactive / redirected stdin
    Read-Host "按 Enter 启动"
  }

  Write-Host "正在启动..." -ForegroundColor Cyan
  switch ($Platform) {
    'windows' { Start-Process -FilePath $outPath -WorkingDirectory $dir }
    'macos'   { Start-Process 'open' -ArgumentList $outPath }
    'linux'   { Start-Process -FilePath $outPath -WorkingDirectory $dir }
  }
}

exit 0

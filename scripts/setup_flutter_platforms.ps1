param(
  [string]$FlutterBat = ""
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

if ([string]::IsNullOrWhiteSpace($FlutterBat)) {
  $command = Get-Command flutter -ErrorAction SilentlyContinue
  if ($null -eq $command) {
    throw "Flutter was not found on PATH. Pass -FlutterBat with an absolute path to flutter.bat."
  }
  $FlutterBat = $command.Source
}

Write-Host "Using Flutter: $FlutterBat"

& $FlutterBat create . --platforms=android,windows
& $FlutterBat pub get

Write-Host "Platform scaffolding complete."

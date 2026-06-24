# Clears locked Flutter web build output, then starts Chrome debug.
$ErrorActionPreference = 'SilentlyContinue'

Get-Process dart -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 1

if (Test-Path build) {
  Remove-Item -Recurse -Force build
}

flutter run -d chrome

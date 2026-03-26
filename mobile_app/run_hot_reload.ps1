param(
  [string]$DeviceId = "R3CN205RZTY",
  [string]$BaseUrl = "http://127.0.0.1:8000"
)

$ErrorActionPreference = "Stop"

$projectRoot = $PSScriptRoot
$adb = Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe"

if (-not (Test-Path $adb)) {
  throw "adb.exe not found: $adb"
}

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  throw "flutter is not on PATH."
}

$deviceList = & $adb devices
$expectedDevice = "$DeviceId`tdevice"

if (-not ($deviceList | Select-String -SimpleMatch $expectedDevice)) {
  $deviceList | Out-Host
  throw "Device '$DeviceId' is not connected."
}

Write-Host "Using device: $DeviceId"
Write-Host "Setting adb reverse tcp:8000 -> tcp:8000"
& $adb -s $DeviceId reverse tcp:8000 tcp:8000

Push-Location $projectRoot
try {
  Write-Host "Starting flutter run..."
  Write-Host "Press 'r' for Hot Reload, 'R' for Hot Restart, 'q' to quit."
  flutter run -d $DeviceId --dart-define=DEFAULT_BASE_URL=$BaseUrl
}
finally {
  Pop-Location
}

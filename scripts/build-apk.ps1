# Build release APK for most Android phones (arm64) without OOM on low-RAM PCs.
$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)

Write-Host "Stopping Gradle daemons to free RAM..."
Push-Location android
& .\gradlew --stop 2>$null
Pop-Location

Write-Host "Building arm64 release APK..."
flutter build apk --release --target-platform android-arm64 --dart-define=API_ORIGIN=https://aims.igenhr.com

$apk = "build\app\outputs\flutter-apk\app-release.apk"
if (Test-Path $apk) {
  $mb = [math]::Round((Get-Item $apk).Length / 1MB, 1)
  Write-Host "Done: $apk ($mb MB)"
} else {
  Write-Error "APK not found at $apk"
  exit 1
}

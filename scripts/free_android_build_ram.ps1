# Free RAM before Flutter/Android builds on low-memory Windows machines.
# Usage (from screen-app-flutter):
#   powershell -ExecutionPolicy Bypass -File scripts\free_android_build_ram.ps1

$ErrorActionPreference = 'SilentlyContinue'

Write-Host '==> Stopping Gradle daemons...'
$gradlew = Join-Path (Split-Path $PSScriptRoot -Parent) 'android\gradlew.bat'
if (Test-Path $gradlew) {
    & $gradlew --stop 2>$null
}

Write-Host '==> Stopping leftover build processes...'
Get-Process -Name java, dart -ErrorAction SilentlyContinue | ForEach-Object {
    try {
        $cmd = (Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)").CommandLine
        if ($cmd -match 'gradle|flutter|dart\.exe|KotlinCompileDaemon|kotlin-daemon') {
            Write-Host "    kill $($_.Id) $($_.ProcessName)"
            Stop-Process -Id $_.Id -Force
        }
    } catch {}
}

Write-Host '==> Clearing Flutter/Gradle temp pressure (safe)...'
$env:GRADLE_OPTS = '-Xmx1536m -Dorg.gradle.daemon=false'
$env:JAVA_TOOL_OPTIONS = '-Xmx1536m'

Write-Host ''
Write-Host 'Done. Close Chrome / unused apps, then run:'
Write-Host '  flutter run -d 32011FDH20058L --android-skip-build-dependency-validation'
Write-Host ''

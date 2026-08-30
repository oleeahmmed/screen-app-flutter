# Flutter branches

| Branch | Purpose |
|--------|---------|
| `main` | Full client (Windows / Linux / macOS + Android). Desktop builds include screenshot monitoring. Android on `main` may still ship legacy MediaProjection native bits — prefer `android` for Play/APK. |
| `android` | Android-only distribution build. **No** screen-capture libraries, MediaProjection service, or `FOREGROUND_SERVICE_MEDIA_PROJECTION` permission. Attendance, tasks, chat, and P2P remain. |

## Build Android APK (no screenshot permission)

```bash
git checkout android
flutter pub get
flutter build apk --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk`

## Keep in sync

When merging feature work from `main` into `android`, re-check:

- `android/app/src/main/AndroidManifest.xml` — must not reintroduce MediaProjection permissions/services
- `MainActivity.kt` — plain `FlutterActivity` only
- No `ScreenshotCaptureHelper.kt` / `MonitorForegroundService.kt` / `android_screenshot_channel.dart`

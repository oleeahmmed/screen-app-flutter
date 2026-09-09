## Step 1: Phone connect করুন

1. Phone-এ **USB debugging ON**
2. USB cable দিয়ে PC-তে connect
3. Phone-এ “Allow USB debugging?” → **Allow**

---

## Step 2: Device ID খুঁজুন

PowerShell খুলে এই command চালান:

```powershell
flutter devices
```

Output-এ আপনার phone এর নামের পাশে **device id** থাকবে। Example:

```
Pixel 7 (mobile)  • 32011FDH20058L • android-arm64
```

এখানে device id = **`32011FDH20058L`**

**অন্য উপায় (adb দিয়ে):**

```powershell
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
& $adb devices
```

Output:

```
List of devices attached
32011FDH20058L    device
```

`device` লেখার বাম পাশের string = আপনার device id।

---

## Step 3: Project folder-এ যান

```powershell
cd "c:\Users\Admin\Desktop\ibit\screenbundle\flutter and django\screen-app-flutter"
```

---

## Step 4: App run করুন (hot reload enable)

```powershell
flutter run -d 32011FDH20058L
```

`32011FDH20058L` এর জায়গায় আপনার device id দিন।

প্রথমবার build হতে ২–৫ মিনিট লাগতে পারে। শেষ হলে phone-এ app open হবে এবং terminal-এ লেখা থাকবে:

```
Flutter run key commands.
r Hot reload.
R Hot restart.
```

---

## Step 5: Code change করার পর

| Key | কাজ |
|-----|-----|
| **`r`** | Hot reload — Dart/UI change দ্রুত দেখা |
| **`R`** | Hot restart — state reset (notification/icon fix-এর জন্য এটা দরকার) |
| **`q`** | Stop |

**Notification/sound fix test করতে:** terminal-এ **`R`** চাপুন (capital R)।

---

## যদি device না দেখায়

```powershell
& $adb kill-server
& $adb start-server
& $adb devices
flutter devices
```

Phone unplug → plug → USB mode **File transfer** রাখুন।

---

**আপনার Pixel 7 এখন connected** — device id: `32011FDH20058L`। সরাসরি চালাতে পারেন:

```powershell
cd "c:\Users\Admin\Desktop\ibit\screenbundle\flutter and django\screen-app-flutter"
flutter run -d 32011FDH20058L
```

---

## Hot reload vs phone-এ স্থায়ী install

### `flutter run` দিয়ে যা দেখছেন

| বিষয় | ব্যাখ্যা |
|--------|----------|
| **Hot reload (`r`)** | শুধু চলমান debug session-এ দ্রুত UI/Dart change দেখায়। App পুরো বন্ধ করে আবার খুললে কিছু change হারাতে পারেন। |
| **Hot restart (`R`)** | App restart করে নতুন code লোড করে। Native change (icon, sound, permission) বা বড় logic change-এ **`R`** দিন। |
| **Terminal `q` বা USB বের করলে** | App phone-এ **থাকে** — আবার icon চাপলে চালু হবে। কিন্তু এটা **debug build** (development), production APK নয়। |
| **Phone backup** | Debug app backup করে অন্য phone-এ নিলে সাধারণত **ভালো কাজ করে না**। স্থায়ী বা শেয়ার করার জন্য release APK build করুন। |

**সংক্ষেপে:** Hot reload দিয়ে test করা update USB কাটলেও debug app-এ কিছুটা থাকতে পারে, কিন্তু **অফিসিয়াল/স্থায়ী install = release APK build**।

---

## Release APK বানানো (phone-এ স্থায়ী install)

Project folder-এ:

```powershell
cd "c:\Users\Admin\Desktop\ibit\screenbundle\flutter and django\screen-app-flutter"
flutter pub get
```

### Recommended (এই PC-তে — কম RAM, OOM এড়াতে)

```powershell
flutter build apk --release --target-platform android-arm64
```

Output: `build\app\outputs\flutter-apk\app-release.apk` (~50–80 MB) — **Pixel 7 / বেশিরভাগ নতুন phone**

পুরনো 32-bit phone-এর জন্য আলাদা:

```powershell
flutter build apk --release --target-platform android-arm
```

### Universal APK (সব ABI একসাথে — বেশি RAM লাগে)

```powershell
flutter build apk --release
```

**`Out of memory` / `Dart snapshot generator failed` হলে:**

1. `flutter clean` চালাবেন **না** (আরও RAM খায়)
2. Gradle daemon বন্ধ করুন: `cd android; .\gradlew --stop; cd ..`
3. Chrome/Cursor অন্য heavy app বন্ধ করুন
4. উপরের **`--target-platform android-arm64`** command ব্যবহার করুন
5. অথবা: `flutter build apk --release --split-per-abi` (৩টো ছোট APK)

Build শেষে APK পাওয়া যাবে:

```
build\app\outputs\flutter-apk\app-release.apk
```

অথবা split build-এ:

```
build\app\outputs\flutter-apk\app-arm64-v8a-release.apk
```

Phone-এ install:

1. APK file phone-এ copy করুন (USB / Google Drive / email)
2. Phone-এ file manager দিয়ে `app-release.apk` tap করুন
3. “Install unknown apps” allow করুন (প্রয়োজন হলে)
4. Install

**একই PC থেকে সরাসরি install (USB + adb):**

```powershell
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
& $adb install -r "build\app\outputs\flutter-apk\app-release.apk"
```

`-r` = আগের app replace করবে (data সাধারণত থাকে)।

### ছোট APK (optional — ABI split)

```powershell
flutter build apk --release --split-per-abi
```

Output:

- `build\app\outputs\flutter-apk\app-arm64-v8a-release.apk` ← **Pixel 7 / অধিকাংশ নতুন phone (2017+)**
- `app-armeabi-v7a-release.apk` ← পুরনো 32-bit-only phone
- `app-x86_64-release.apk` ← emulator

**অন্য device-এ “App not installed” হলে:**

1. **সঠিক APK দিন** — নতুন phone-এ `arm64-v8a`, পুরনো budget phone-এ `armeabi-v7a` চেষ্টা করুন।
2. **আগের AIMS uninstall** করুন — অন্য source (debug / পুরনো APK) থেকে install থাকলে signature মিলবে না।
3. **WhatsApp দিয়ে পাঠাবেন না** — বড় APK corrupt হয়; USB, Google Drive, বা email ব্যবহার করুন।
4. Settings → **Install unknown apps** — file manager / Drive-এ allow করুন।

`releases/` folder-এ friendly নামে copy করা APK:

- `aims-v1.0.6-build42-arm64.apk` — বেশিরভাগ officer phone
- `aims-v1.0.6-build42-armv7.apk` — পুরনো 32-bit phone

### Production API URL (optional)

Local server না, live server:

```powershell
flutter build apk --release --dart-define=API_ORIGIN=https://aims.igenhr.com
```

### Windows desktop installer (optional)

```powershell
flutter build windows --release
```

Output: `build\windows\x64\runner\Release\`

---

## Debug vs Release — কখন কোনটা

| উদ্দেশ্য | Command |
|---------|---------|
| দ্রুত development + hot reload | `flutter run -d DEVICE_ID` |
| Phone-এ স্থায়ী রাখা / অন্যকে দেওয়া | `flutter build apk --release` |
| Play Store | `flutter build appbundle --release` |

---

## Chat আরো ভালো করতে — পরবর্তী priority

ইতিমধ্যে আছে: inbox, bubbles, reactions, reply/forward/edit/delete, swipe-reply, wallpaper, profile photo, long-press action bar।

**High priority (WhatsApp feel):**

1. **Date separators** — “Today”, “Yesterday” মেসেজের মাঝে
2. **Scroll-to-bottom FAB** — উপরে scroll করলে নিচে যাওয়ার বাটন
3. **Pin / Mute / Archive chat** — inbox list-এ
4. **Hold-to-record voice** — mic বাটন ধরে voice message
5. **@mentions** — group chat-এ
6. **Read/delivered ticks** — sent ✓, delivered ✓✓, read (blue)

**Medium:**

7. Link preview (URL থাকলে thumbnail)
8. Jump to quoted message (reply tap করলে original message)
9. Starred messages screen (star এখন local — persist + list page)
10. Native Share (`share_plus`) — Share menu থেকে সরাসরি apps-এ

**Native change (hot reload নয় — `R` বা rebuild):**

- Notification icon/sound
- New package (`pasteboard`, `share_plus`, etc.) → `flutter pub get` তারপর **`R`** বা `flutter run`
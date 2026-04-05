# Flutter Windows — Release build ও Installer (ধাপে ধাপে)

এই ডকুমেন্ট `igen_app` (প্রজেক্ট ফোল্ডার: `screen-app-flutter`) এর জন্য। Windows এ Flutter ডেস্কটপ অ্যাপ রিলিজ বিল্ড করতে ও ইনস্টলার তৈরি করতে ব্যবহার করুন।

---

## ১. যা লাগবে (প্রerequisites)

1. **Windows 10/11 (64-bit)** — ডেভেলপমেন্ট মেশিন।
2. **Flutter SDK** — স্টেবল চ্যানেল, ডেস্কটপ সাপোর্ট চালু।
   ```powershell
   flutter doctor -v
   ```
3. **Visual Studio 2022** — ইনস্টল করার সময় workload হিসেবে **“Desktop development with C++”** চেক করুন (Windows SDK + MSVC টুলস)।
4. **Flutter এ Windows ডেস্কটপ সক্ষম** থাকতে হবে:
   ```powershell
   flutter config --enable-windows-desktop
   ```

`flutter doctor` এ Windows toolchain সবুজ/ঠিক না থাকলে আগে সেটা ঠিক করুন, তারপর বিল্ড করুন।

---

## ২. প্রজেক্টে যান ও ডিপেন্ডেন্সি নিন

```powershell
cd "C:\Users\Admin\Desktop\ibit\screenbundle\screen-app-flutter"
flutter pub get
```

---

## ৩. ভার্সন সেট করুন (`pubspec.yaml`)

রিলিজের আগে `pubspec.yaml` এর `version` লাইন আপডেট করুন:

```yaml
version: 1.0.1+2
```

- `1.0.1` = ইউজার-ফেসিং ভার্সন (মেজর.মাইনর.প্যাচ)।
- `+2` = বিল্ড নম্বর (প্রতি স্টোর/রিলিজে বাড়ান)।

Windows এ Flutter এই ভার্সন ফাইল প্রপার্টিতে ব্যবহার করে।

---

## ৪. রিলিজ বিল্ড (EXE + DLL — ইনস্টলারের raw আউটপুট)

```powershell
flutter build windows --release
```

ঐচ্ছিক: নির্দিষ্ট ভার্সন স্ট্রিং দিতে চাইলে:

```powershell
flutter build windows --release --build-name=1.0.1 --build-number=2
```

### আউটপুট কোথায়?

সাধারণ পাথ:

```
screen-app-flutter\build\windows\x64\runner\Release\
```

এখানে **`igen_app.exe`** (আপনার অ্যাপের নাম `pubspec.yaml` এর `name` অনুযায়ী হতে পারে) এবং প্রয়োজনীয় **`.dll`**, **`data`** ফোল্ডার ইত্যাদি থাকবে।

**গুরুত্বপূর্ণ:** শুধু `.exe` কপি করলে চলবে না — পুরো **`Release`** ফোল্ডারটাই ডিস্ট্রিবিউট করতে হয় (সব DLL ও `data` সহ)।

### টেস্ট

`Release` ফোল্ডারে ডাবল-ক্লিক করে exe চালিয়ে দেখুন, অথবা:

```powershell
cd build\windows\x64\runner\Release
.\igen_app.exe
```

নাম ভিন্ন হলে `dir *.exe` দিয়ে নিশ্চিত হন।

---

## ৫. Windows Installer তৈরির উপায় (একটি বেছে নিন)

নিচে তিনটি সাধারণ পথ। আপনার দল/ডিস্ট্রিবিউশন চ্যানেল অনুযায়ী একটি যথেষ্ট।

---

### পথ A — **ZIP / ফোল্ডার কপি** (দ্রুত, কোনো ইনস্টলার নয়)

1. `Release` ফোল্ডারটা জিপ করুন (উদাহরণ: `igen_app-1.0.1-windows-x64.zip`)।
2. ইউজার জিপ আনজিপ করে ফোল্ডার থেকে `igen_app.exe` চালাবে।

সুবিধা: সহজ। অসুবিধা: স্টার্ট মেনু/আনইনস্টলার/আপডেট ট্র্যাক অটো নয়।

---

### পথ B — **MSIX প্যাকেজ** (Microsoft Store বা সাইডলোডের জন্য ভালো)

MSIX একটি আধুনিক Windows প্যাকেজ ফরম্যাট; স্বাক্ষরিত হলে “Add or remove programs” এ দেখা যায়।

**১)** `pubspec.yaml` এ `dev_dependencies` এ যোগ করুন:

```yaml
dev_dependencies:
  # ... existing ...
  msix: ^3.16.8
```

**২)** একই ফাইলে নিচের মতো `msix_config` ব্লক যোগ করুন (মান আপনার কোম্পানি/অ্যাপ অনুযায়ী বদলান):

```yaml
msix_config:
  display_name: iGen App
  publisher_display_name: Your Company Name
  identity_name: com.yourcompany.igenapp
  msix_version: 1.0.1.0
  logo_path: windows\runner\resources\app_icon.ico
  capabilities: internetClient
```

- `identity_name` — রিভার্স DNS স্টাইল, ইউনিক হতে হবে।
- `msix_version` — চার অংক: `মেজর.মাইনর.প্যাচ.বিল্ড`।
- আইকন পাথ আপনার প্রজেক্টে যা আছে সেটা দিন।

**৩)** প্যাকেজ তৈরি:

```powershell
flutter pub get
dart run msix:create
```

আউটপুট সাধারণত `build\windows\x64\runner\Release\` অথবা টুল যে পাথ দেখায় সেখানে `.msix` ফাইল।

**৪)** সাইডলোড/টেস্টের জন্য কখনও **ডেভেলপার মোড** বা সার্টিফিকেট লাগতে পারে। স্টোরে দিতে হলে Microsoft Partner Center এর নিয়ম অনুসরণ করুন।

আরও ডিটেইল: [msix package on pub.dev](https://pub.dev/packages/msix)।

---

### পথ C — **Inno Setup** (`.exe` সেটআপ — খুব জনপ্রিয়)

একটি ক্লাসিক “Next → Next → Install” ইনস্টলার।

**১)** [Inno Setup](https://jrsoftware.org/isdl.php) ইনস্টল করুন।

**২)** নতুন স্ক্রিপ্ট তৈরি করুন; নিচের মতো সেকশন সাজান (পাথ `Release` ফোল্ডারের সাথে মিলিয়ে নিন):

```iss
#define MyAppName "iGen App"
#define MyAppVersion "1.0.1"
#define MyAppPublisher "Your Company"
#define MyAppExeName "igen_app.exe"
#define ReleaseDir "C:\Users\Admin\Desktop\ibit\screenbundle\screen-app-flutter\build\windows\x64\runner\Release"

[Setup]
AppId={{YOUR-GUID-HERE}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
OutputDir=.
OutputBaseFilename=igen_app-{#MyAppVersion}-setup
Compression=lzma2
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64
PrivilegesRequired=lowest

[Files]
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{userdesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop icon"; GroupDescription: "Additional icons:"

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
```

- `AppId` — একবার জেনারেট করা **GUID** ব্যবহার করুন (Inno Setup এ Tools → Generate GUID)।
- `ReleaseDir` — আপনার মেশিনে `flutter build windows --release` এর পরের আসল পাথ দিন।

**৩)** Inno Setup এ স্ক্রিপ্ট কম্পাইল করুন → একটি `...-setup.exe` পাবেন।

---

### পথ D — **NSIS** (অনুরূপ — স্ক্রিপ্ট ভিত্তিক সেটআপ)

[NSIS](https://nsis.sourceforge.io/) দিয়েও ফোল্ডার প্যাকেজ করা যায়। Flutter অফিসিয়ালি একটি স্ট্যান্ডার্ড টেমপ্লেট দেয় না; কমিউনিটি গাইড অনুসরণ করে `.nsi` স্ক্রিপ্ট লিখতে হয়।

---

## ৬. রিলিজ চেকলিস্ট (সংক্ষেপে)

| ধাপ | কাজ |
|-----|-----|
| 1 | `flutter doctor` ঠিক আছে কিনা |
| 2 | `pubspec.yaml` ভার্সন আপডেট |
| 3 | `flutter build windows --release` |
| 4 | `Release` ফোল্ডারে ম্যানুয়ালি অ্যাপ চালিয়ে টেস্ট |
| 5 | ইনস্টলার (MSIX / Inno / ZIP) বেছে নিয়ে বানান |
| 6 | ভিন্ন PC তে ক্লিন ইনস্টল টেস্ট |

---

## ৭. সমস্যা হলে

- **বিল্ড ফেইল:** Visual Studio C++ workload ও Windows SDK ইনস্টল আছে কিনা।
- **অ্যাপ চলে না অন্য PC তে:** সব DLL ও `data` ফোল্ডার একসাথে কপি হয়েছে কিনা; শুধু exe নয়।
- **WebView / MSVC রানটাইম:** কিছু প্লাগইন অন্য মেশিনে **Visual C++ Redistributable** চায় — প্রয়োজনে Microsoft সাইট থেকে x64 redistributable ইনস্টলারের সাথে বা আলাদা নোট দিন।

---

## দ্রুত রেফারেন্স কমান্ড

```powershell
cd "C:\Users\Admin\Desktop\ibit\screenbundle\screen-app-flutter"
flutter pub get
flutter build windows --release
# আউটপুট: build\windows\x64\runner\Release\
```

এই ফাইলটি প্রজেক্টের `docs\WINDOWS_RELEASE_INSTALLER.md` এ সংরক্ষিত।

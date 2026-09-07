This file was provided by: https://www.dll-files.com/

If you downloaded it from somewhere else, please let us know: info@dll-files.com

DLL-Files.com is owned and operated by Tilf AB, Sweden. The collection of DLL files as a whole (falls under the “collection copyright” laws) are © Copyright Tilf AB

The individual DLL files are provided free of charge with the understanding that the user is familiar with their use.

If you need help installing the file, please see:
https://www.dll-files.com/support/
or ask your question in the forum:
https://forum.dll-files.com/

DISCLAIMER AND LIMITATION OF LIABILITY

The Following Refers to all Files with the Extension of "dll" or dlls compressed as "zip".

All files are provided on an as is basis. No guarantees or warranties are given or implied. Downloading files from this site is free of charge and the user assumes all risks of any damages that may occur, including but not limited to loss of data, damages to hardware, or loss of business profits. We do our best to ensure that all files are virus-free using available means. However, all files have not been tested for functionality or contamination. Many have been sent to us by visitors like yourself. Thus, we suggest that you do a virus scan using an up-to-date version of an anti-virus program before use. Please use at your own risk.


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
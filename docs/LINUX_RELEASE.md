# Flutter Linux — Debian/Ubuntu Release (ধাপে ধাপে)

এই ডকুমেন্ট `aims` (প্রজেক্ট ফোল্ডার: `screen-app-flutter`) এর জন্য। **Debian, Ubuntu** এবং অন্যান্য `.deb`-সাপোর্টিং ডিস্ট্রোতে ইনস্টল করার জন্য রিলিজ বিল্ড ও প্যাকেজ তৈরি করতে ব্যবহার করুন।

---

## ১. যা লাগবে (prerequisites)

1. **Ubuntu 22.04+ / Debian 12+ (64-bit)** — বিল্ড মেশিন (x86_64 বা arm64)।
2. **Flutter SDK** — stable channel, Linux desktop enabled:
   ```bash
   flutter doctor -v
   flutter config --enable-linux-desktop
   ```
3. **Build tools** — স্ক্রিপ্ট চালালে `apt` দিয়ে ইনস্টল হবে, অথবা ম্যানুয়ালি:
   ```bash
   sudo apt update
   sudo apt install -y \
     clang cmake ninja-build pkg-config \
     libgtk-3-dev libblkid-dev liblzma-dev \
     libsecret-1-dev libjsoncpp-dev \
     libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
     dpkg-dev
   ```

---

## ২. ভার্সন সেট করুন

`pubspec.yaml` এ:

```yaml
version: 1.0.0+1
```

- `1.0.0` = ইউজার-ফেসিং ভার্সন (`.deb` ও `.tar.gz` নামে ব্যবহার)।
- `+1` = বিল্ড নম্বর।

---

## ৩. এক কমান্ডে বিল্ড + `.deb` + `.tar.gz`

```bash
cd screen-app-flutter
bash scripts/build_linux_release.sh
```

### আউটপুট (`dist/` ফোল্ডার)

| ফাইল | ব্যবহার |
|------|---------|
| `aims_1.0.0_amd64.deb` | Ubuntu/Debian এ `sudo apt install ./aims_*.deb` |
| `aims-linux-amd64-1.0.0.tar.gz` | পোর্টেবল — extract করে `./run-aims.sh` |

### API সার্ভার পরিবর্তন (optional)

```bash
API_ORIGIN=https://aims.igenhr.com bash scripts/build_linux_release.sh
```

### অন্যান্য ফ্ল্যাগ

```bash
bash scripts/build_linux_release.sh --skip-apt    # apt install ছাড়া (deps আগে থেকে থাকলে)
bash scripts/build_linux_release.sh --deb-only    # শুধু .deb
bash scripts/build_linux_release.sh --tar-only    # শুধু .tar.gz
```

---

## ৪. `.deb` ইনস্টল (যেকোনো Ubuntu/Debian)

```bash
cd dist
sudo apt install ./aims_1.0.0_amd64.deb
```

অথবা:

```bash
sudo dpkg -i aims_1.0.0_amd64.deb
sudo apt -f install   # dependency missing হলে
```

ইনস্টলের পর:

- **অ্যাপ লঞ্চার** → "AIMS" সার্চ করুন
- **টার্মিনাল** → `aims`

### sudo ছাড়া ইনস্টল (একই মেশিনে, password নেই)

```bash
bash scripts/install_local.sh dist/aims_1.0.0_amd64.deb
export PATH="$HOME/.local/bin:$PATH"
aims
```

### ইনস্টল হচ্ছে না? (সাধারণ কারণ)

Ubuntu 25.10 / নতুন Debian-এ পুরনো `.deb` fail করতে পারে — library নাম বদলেছে:

| পুরনো Depends | নতুন (Ubuntu 25.10) |
|--------------|---------------------|
| `libgtk-3-0` | `libgtk-3-0t64` |
| `libjsoncpp25` | `libjsoncpp26` |

**সমাধান:** সর্বশেষ build নিন (`bash scripts/build_linux_release.sh`) — নতুন `.deb`-এ দুটোই সাপোর্ট আছে।

চেক করুন:

```bash
apt install -s ./aims_1.0.0_amd64.deb
```

`Unable to satisfy dependencies` না দেখালে `sudo apt install ./aims_*.deb` কাজ করবে।

### আনইনস্টল

```bash
sudo apt remove aims
```

---

## ৫. অন্য Linux ব্যবহারকারীকে দেবেন কীভাবে

তাদের শুধু `dist/` থেকে **একটা ফাইল** পাঠান:

| ফাইল | কখন দেবেন |
|------|-----------|
| `aims_1.0.0_amd64.deb` | Ubuntu/Debian — সবচেয়ে সহজ |
| `aims-linux-amd64-1.0.0.tar.gz` | sudo নেই / অন্য distro |

**তাদের কমান্ড (.deb):**

```bash
sudo apt install ./aims_1.0.0_amd64.deb
aims
```

**তাদের কমান্ড (portable, sudo ছাড়া):**

```bash
tar -xzf aims-linux-amd64-1.0.0.tar.gz
cd aims-linux-amd64-1.0.0
./run-aims.sh
```

**ঐচ্ছিক — screenshot monitoring:**

```bash
sudo apt install gnome-screenshot
```

---

## ৬. ইউজার মেশিনে runtime dependencies

`.deb` ইনস্টল করলে অধিকাংশ dependency অটো resolve হয়। পোর্টেবল ব্যবহার করলে:

```bash
sudo apt install libgtk-3-0 libsecret-1-0 libgstreamer1.0-0 libgstreamer-plugins-base1.0-0
```

স্ক্রিনশট মনিটরিং (optional):

```bash
sudo apt install gnome-screenshot    # X11 / GNOME
sudo apt install grim                # Wayland
```

---

## ৭. সাপোর্টেড প্ল্যাটফর্ম

| OS | Architecture | প্যাকেজ |
|----|--------------|---------|
| Ubuntu 20.04+ | amd64, arm64 | `.deb` |
| Debian 11+ | amd64, arm64 | `.deb` |
| Linux Mint, Pop!_OS, Zorin | amd64 | `.deb` |
| অন্যান্য distro | amd64 | `.tar.gz` (portable) |

---

## ৮. চেকলিস্ট

| ধাপ | কাজ |
|-----|-----|
| 1 | `flutter doctor -v` সবুজ |
| 2 | `pubspec.yaml` version bump |
| 3 | `bash scripts/build_linux_release.sh` |
| 4 | `sudo apt install ./dist/aims_*.deb` দিয়ে টেস্ট |
| 5 | `dist/` থেকে `.deb` ও `.tar.gz` ডিস্ট্রিবিউট করুন |

---

## ৯. Windows এর সাথে তুলনা

| Windows | Linux (Debian/Ubuntu) |
|---------|------------------------|
| `scripts/build_windows_installer.ps1` | `scripts/build_linux_release.sh` |
| `innoscript.iss` → `.exe` installer | `dpkg-deb` → `.deb` package |
| `build/windows/x64/runner/Release/` | `build/linux/x64/release/bundle/` |

Windows গাইড: [`docs/WINDOWS_RELEASE_INSTALLER.md`](WINDOWS_RELEASE_INSTALLER.md)

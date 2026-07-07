# P2P File Transfer & Android APK

## Server এ কী কী চালু থাকতে হবে (P2P এর জন্য)

P2P file transfer এ **ফাইল সার্ভারে যায় না** — শুধু session তৈরি ও WebRTC signaling হয়। তবে নিচের সেবাগুলো **অবশ্যই** চালু থাকতে হবে:

### 1. Django ASGI (WebSocket)

শুধু `gunicorn` (WSGI) দিয়ে WebSocket কাজ করবে না। **Daphne** বা **uvicorn** দিয়ে ASGI চালান:

```bash
cd screen
daphne -b 0.0.0.0 -p 8000 config.asgi:application
```

Production এ nginx reverse proxy দিয়ে `/ws/` path **WebSocket upgrade** সহ proxy করুন (`proxy_http_version 1.1`, `Upgrade`, `Connection` headers)।

### 2. Redis (অবশ্যই)

`CHANNEL_LAYERS` Redis ব্যবহার করে। Redis বন্ধ থাকলে দুই ডিভাইসের মধ্যে signaling message পৌঁছাবে না।

```bash
redis-server
# অথবা Docker:
docker run -d -p 6379:6379 redis:7
```

Environment:

- `REDIS_HOST=127.0.0.1`
- `REDIS_PORT=6379`

### 3. REST API

এই endpoint গুলো কাজ করতে হবে (JWT login সহ):

- `GET /api/p2p/ice-servers/`
- `POST /api/p2p/session/create/`
- `POST /api/p2p/session/join/`
- WebSocket: `wss://<host>/ws/p2p/<session_id>/?token=<jwt>`

### 4. TURN server (মোবাইল / strict NAT এর জন্য সুপারিশকৃত)

শুধু STUN অনেক সময় mobile data বা office firewall এ কাজ করে না। `.env` এ যোগ করুন:

```env
STUN_URL=stun:stun.l.google.com:19302
TURN_URL=turn:your-turn-server:3478
TURN_USERNAME=your_user
TURN_PASSWORD=your_pass
```

[coturn](https://github.com/coturn/coturn) self-hosted TURN হিসেবে ব্যবহার করা যায়।

### 5. HTTPS / WSS

Production app `https://aims.igenhr.com` ব্যবহার করে — WebSocket automatically `wss://` হয়।

---

## P2P টেস্ট চেকলিস্ট

1. **দুই আলাদা অ্যাকাউন্ট** — একই ফোনে sender + receiver করা যাবে না (`Cannot join your own session`)।
2. Sender: Alerts → P2P → Send File → QR/code শেয়ার করুন।
3. Receiver: Receive → code দিন → Accept করুন।
4. Status panel: Signaling → Peer found → WebRTC → Connected → Transfer % দেখাবে।
5. Connect না হলে: Redis চালু আছে কিনা, Daphne/ASGI চালু আছে কিনা, nginx WSS proxy ঠিক আছে কিনা দেখুন।

---

## Android APK বানানো

### দ্রুত build (নতুন design এর জন্য clean build)

```powershell
cd "flutter and django\screen-app-flutter"
powershell -ExecutionPolicy Bypass -File scripts\build_android_apk.ps1
```

Script automatically runs `flutter clean` so old UI/assets are not cached.

অন্য API URL:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\build_android_apk.ps1 -ApiOrigin "https://your-server.com"
```

### পুরনো design দেখালে

1. **পুরনো app uninstall** করুন (Settings → Apps → Aims → Uninstall)
2. `pubspec.yaml`-এ version বাড়ান (যেমন `1.0.2+2` → `1.0.3+3`)
3. আবার build script চালান
4. **নতুন APK** install করুন — `dist/aims-android-v*-b*.apk`
5. Profile-এ version `1.0.2 (2)` বা তার উপরে দেখতে হবে

### ম্যানুয়াল build

```powershell
flutter clean
flutter pub get
flutter build apk --release --build-number=2 --dart-define=API_ORIGIN=https://aims.igenhr.com
```

Output: `build/app/outputs/flutter-apk/app-release.apk`

### Play Store / signing

Release signing এর জন্য `android/key.properties` এবং keystore সেটআপ করুন (Flutter official docs: [Android deployment](https://docs.flutter.dev/deployment/android))।

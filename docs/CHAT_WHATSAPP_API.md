# AIMS Chat API — WhatsApp-style Frontend Guide

> Source of truth: Flutter chat (`lib/pages/chat_page.dart`, `call_service.dart`, `chat_p2p_file_service.dart`) + Django (`screen/screenshots/api/`).  
> Same APIs on **main** (desktop) and **android** branches — chat/call contracts are identical.  
> Production origin: `https://aims.igenhr.com`  
> Local override: `--dart-define=API_ORIGIN=http://<host>:8000`

---

## 0. Base URLs & auth (do this first)

| Kind | Pattern |
|------|---------|
| REST | `{API_ORIGIN}/api/...` |
| Chat WebSocket | `{ws\|wss}://{host}/ws/chat/?token=<JWT_ACCESS>` |
| P2P / Call WebRTC WS | `{ws\|wss}://{host}/ws/p2p/<session_id>/?token=<JWT_ACCESS>` |

**Every REST call** (unless noted):

```http
Authorization: Bearer <access_token>
Content-Type: application/json
Accept: application/json
```

Multipart uploads: omit JSON `Content-Type`; browser/Flutter sets boundary automatically. Still send `Authorization`.

**Login (get JWT):**

```http
POST /api/auth/login/
Content-Type: application/json

{ "username": "...", "password": "..." }
```

Use `access` from the response as Bearer token. Refresh via `/api/auth/refresh/` (or legacy `/api/token/refresh/`).

**Typical errors:**

| Status | Body shape |
|--------|------------|
| 400 | `{ "error": "..." }` |
| 401 | missing/invalid JWT |
| 403 | `{ "error_code": "SUBSCRIPTION_EXPIRED", "message": "..." }` or company/access denial |
| 404 | `{ "error": "..." }` |

---

## 1. Recommended frontend build order (WhatsApp-like)

Implement in this order so each step is testable:

1. Auth + connect `/ws/chat/`
2. Inbox: users + groups list
3. Open DM thread + pagination + mark read
4. Send text + reply
5. Realtime: new message, typing, presence, read receipts
6. Image / file / voice send
7. Reactions (👍 ❤️ …)
8. Edit / delete (DM only)
9. Group CRUD + group messages + group reactions
10. Audio / video call (P2P session + signaling)
11. P2P file transfer from chat
12. Push / notification hooks (optional polish)

---

## 2. Shared message object (DM)

Returned by conversation load, send, edit, and WS `chat_message` (field names may be slightly flatter on WS — map both).

```json
{
  "id": 123,
  "sender": 10,
  "sender_username": "oleee",
  "sender_name": "Oleee",
  "sender_avatar": "https://ui-avatars.com/api/?name=...",
  "receiver": 20,
  "receiver_username": "peer",
  "receiver_name": "Peer",
  "message": "Hello",
  "message_type": "text",
  "image": null,
  "image_url": null,
  "file_attachment": null,
  "file_url": null,
  "file_name": null,
  "voice_message": null,
  "voice_url": null,
  "is_e2ee": false,
  "ciphertext": null,
  "nonce": null,
  "e2ee_version": null,
  "is_read": false,
  "is_deleted": false,
  "is_edited": false,
  "edited_at": null,
  "is_own": true,
  "timestamp": "2026-04-01T12:00:00Z",
  "reply_to": 100,
  "reply": {
    "id": 100,
    "sender_id": 20,
    "sender_name": "Peer",
    "message_type": "text",
    "preview": "Earlier message",
    "is_deleted": false
  },
  "reactions": [
    {
      "emoji": "👍",
      "count": 2,
      "user_ids": [10, 20],
      "reacted_by_me": true
    }
  ],
  "created_at": "...",
  "updated_at": "..."
}
```

**`message_type`:** `text` | `image` | `file` | `voice`

**Reply preview rules (server):** deleted → `"Message deleted"`; image → `"Photo"`; voice → `"Voice message"`; file → `"File: <name>"`.

---

## 3. Inbox — company users (DM list)

### `GET /api/chat/users/`

**200:** JSON **array**

```json
[
  {
    "id": 20,
    "username": "peer",
    "email": "...",
    "first_name": "...",
    "last_name": "...",
    "full_name": "Peer Name",
    "designation": "Developer",
    "employee_id": 55,
    "is_online": true,
    "unread_count": 3,
    "last_message_at": "2026-04-01T12:00:00Z",
    "last_message": "You: Photo",
    "last_message_raw": "...",
    "last_seen": "...",
    "profile_photo_url": "https://..."
  }
]
```

**UI:** WhatsApp chat list rows (avatar, name, last preview, unread badge, online dot).

---

## 4. Direct conversation — load + pagination

### `GET /api/chat/conversation/<user_id>/`

| Query | Type | Notes |
|-------|------|--------|
| `limit` | int | 1–100, default **40** |
| `before_id` | int | older messages (scroll up) |
| `after_id` | int | newer messages |

**200 (preferred):**

```json
{
  "results": [ /* ChatMessage[] */ ],
  "has_more": true
}
```

**Legacy:** bare array of messages (no query params).

Opening a conversation also marks messages read server-side.

---

## 5. Send DM — text, reply, media, voice

### `POST /api/chat/send/`

#### 5.1 Text / reply (JSON)

```json
{
  "receiver_id": 20,
  "message": "Hello",
  "reply_to_id": 100
}
```

- `reply_to_id` optional (alias: `reply_to`)
- **201:** full message object
- Server broadcasts WS `chat_message` to company room

#### 5.2 Image (multipart)

| Field | Value |
|-------|--------|
| `receiver_id` | int |
| `message` | optional caption |
| `reply_to_id` | optional |
| `image` | file ≤ **10MB**; jpeg/png/gif/webp |

#### 5.3 File (multipart)

| Field | Value |
|-------|--------|
| `receiver_id` | int |
| `message` | optional |
| `reply_to_id` | optional |
| `file` | ≤ 10MB; pdf/office/zip/video/audio/text/json/… |

#### 5.4 Voice (multipart)

| Field | Value |
|-------|--------|
| `receiver_id` | int |
| `message` | usually `""` |
| `reply_to_id` | optional |
| `voice_message` | audio file |

---

## 6. Edit & delete (DM only)

### Edit — `PATCH /api/chat/messages/<message_id>/`

```json
{ "message": "Updated text" }
```

- Only **own text** messages  
- **200:** updated message (`is_edited: true`)

### Delete — `DELETE /api/chat/messages/<message_id>/`

**200:** `{ "message": "Message deleted" }` (soft delete)

> Group messages: **no** edit/delete REST in current backend.

---

## 7. Reactions (like WhatsApp)

Allowed emojis only:

`👍` `❤️` `😂` `😮` `😢` `🙏` `👏` `🔥`

### Direct

| Method | Path |
|--------|------|
| `POST` | `/api/chat/messages/<message_id>/reactions/` |
| `DELETE` | `/api/chat/messages/<message_id>/reactions/` |

**POST body:**

```json
{ "emoji": "👍" }
```

**Behavior:** same emoji again → **remove**; different emoji → **replace** (one reaction per user).

**200:**

```json
{
  "message_id": 123,
  "reactions": [
    { "emoji": "👍", "count": 1, "user_ids": [10], "reacted_by_me": true }
  ]
}
```

**WS fan-out:** `type: "message_reaction"`, `chat_type: "direct"`, + reactions list.

### Group

| Method | Path |
|--------|------|
| `POST` / `DELETE` | `/api/chat/groups/<group_id>/messages/<message_id>/reactions/` |

Same body/response; response may include `group_id`. WS: `chat_type: "group"`.

Flutter UI uses **POST toggle** only (DELETE helper exists but unused).

---

## 8. Read receipts & mark all

### Mark one peer read — `POST /api/chat/mark-read/`

```json
{ "sender_id": 20 }
```

**200:** `{ "message": "Messages marked as read" }`  
**WS:** `{ "type": "messages_read", "reader_id": <me>, "sender_id": 20 }`

### Mark everything — `POST /api/chat/mark-all-read/`

```json
{}
```

**200:** `{ "message": "...", "direct_marked": N, "groups_updated": N }`

### Unread counts (optional) — `GET /api/chat/unread-count/`

```json
{
  "total_unread": 5,
  "unread_by_sender": [{ "sender": 20, "count": 3 }]
}
```

Flutter badge often uses **notifications** unread instead; this endpoint still works.

---

## 9. Online presence (REST snapshot)

### `GET /api/chat/online-users/`

Array of `{ user, username, full_name, is_online, last_seen }`.

**Prefer live WS** `user_status` + `is_online` on `/chat/users/` for the list UI.

---

## 10. Groups

### List — `GET /api/chat/groups/`

```json
[
  {
    "id": 1,
    "name": "Dev Team",
    "description": "...",
    "company": 1,
    "created_by": 10,
    "created_by_username": "oleee",
    "project": null,
    "project_name": null,
    "visibility_mode": "shared",
    "member_count": 8,
    "unread_count": 2,
    "last_message": "You: Hi",
    "last_message_at": "...",
    "avatar_url": "...",
    "can_manage": true,
    "is_active": true,
    "created_at": "...",
    "updated_at": "..."
  }
]
```

`visibility_mode`: `shared` | `personal`  
(`personal` = message can target subset via `recipient_ids`)

### Create — `POST /api/chat/groups/`

```json
{
  "name": "Dev Team",
  "description": "optional",
  "member_ids": [20, 21, 22],
  "visibility_mode": "shared"
}
```

**201:** group object

### Detail — `GET /api/chat/groups/<group_id>/`

### Update / avatar — `PATCH /api/chat/groups/<group_id>/` (admin)

JSON: `name`, `description`, optional `remove_avatar`  
Multipart: field `avatar` (image file)

### Delete — `DELETE /api/chat/groups/<group_id>/`

**204**-style success with body `{ "message": "Group deleted successfully" }`

---

## 11. Group messages

### Load — `GET /api/chat/groups/<group_id>/messages/`

Same query as DM: `limit`, `before_id`, `after_id` → `{ results, has_more }`  
Updates membership `last_read_at`.

### Send — `POST /api/chat/groups/<group_id>/messages/`

**JSON:**

```json
{
  "message": "Hello group",
  "reply_to_id": 50,
  "recipient_ids": [20, 21]
}
```

`recipient_ids` optional (personal visibility).

**Multipart:** same fields + `image` | `file` | `voice_message` (same size/type rules as DM).

**201 — group message shape:**

```json
{
  "id": 50,
  "group": 1,
  "sender": 10,
  "sender_username": "oleee",
  "sender_full_name": "Oleee",
  "sender_avatar": "...",
  "message": "Hello group",
  "message_type": "text",
  "image_url": null,
  "file_url": null,
  "file_name": null,
  "voice_url": null,
  "is_own": true,
  "timestamp": "...",
  "reply_to": null,
  "reply": null,
  "recipient_ids": [],
  "reactions": [],
  "created_at": "...",
  "updated_at": "..."
}
```

**WS to clients:** `type: "group_message"`

---

## 12. Group members

| Method | Path | Body |
|--------|------|------|
| `GET` | `/api/chat/groups/<id>/members/` | — |
| `POST` | same | `{ "member_ids": [20, 21] }` (or `user_ids`) |
| `PATCH` | `.../members/<member_id>/` | `{ "role": "admin" \| "member" }` |
| `DELETE` | `.../members/<member_id>/` | leave / kick |

Member object: `{ id, group, user, username, full_name, role, last_read_at, joined_at }`

---

## 13. WebSocket — `/ws/chat/?token=<JWT>` (required for WhatsApp feel)

Connect after login. Reconnect on token refresh.

### Client → server

| `type` | Payload | Feature |
|--------|---------|---------|
| `typing` | `{ "receiver_id": 20, "is_typing": true }` | DM typing |
| `group_typing` | `{ "group_id": 1, "is_typing": true }` | group typing |
| `mark_read` | `{ "sender_id": 20 }` | optional (Flutter prefers REST) |
| `group_mark_read` | `{ "group_id": 1 }` | group read |
| `call_invite` | see §14 | ringing |
| `call_accept` | `{ "call_id", "caller_id" }` | accept |
| `call_reject` | `{ "call_id", ... }` | decline |
| `call_hangup` | `{ "call_id", ... }` | end |
| `call_dismiss` | `{ "call_id", ... }` | multi-device dismiss |
| `call_offer` / `call_answer` / `call_ice` | SDP/ICE | HTTP/WS fallback (Flutter prefers P2P WS) |

### Server → client (handle these)

| `type` | Use |
|--------|-----|
| `chat_message` | append DM bubble |
| `group_message` | append group bubble |
| `typing_indicator` | `{ sender_id, receiver_id, is_typing, sender_username }` |
| `group_typing` | `{ group_id, sender_id, is_typing }` |
| `user_status` | `{ user_id, username, is_online }` |
| `messages_read` | blue ticks / read state |
| `message_reaction` | live reaction update |
| `call_invite` / `call_accept` / `call_reject` / `call_hangup` / `call_dismiss` / `call_error` | call UI |
| `notification` | tray / in-app (`notification_type`: `new_message`, `new_group_message`, `call_invite`, …) |
| `error` | access lost |

Close codes of interest: `4001` / `4002` / `4003` (auth / company / subscription).

---

## 14. Audio & video calls (exact Flutter flow)

Calls are **1:1 WebRTC**. Signaling uses:

1. P2P session REST  
2. Hidden chat control messages via `POST /api/chat/send/`  
3. Chat WS call events  
4. WebRTC SDP/ICE on `/ws/p2p/<session_id>/`

### Step A — ICE servers

```http
GET /api/p2p/ice-servers/
```

**200:** `{ "ice_servers": [ { "urls": "stun:..." }, ... ] }`

### Step B — Caller creates session

```http
POST /api/p2p/session/create/
```

```json
{
  "file_name": "__CALL__|audio|<localCallId>",
  "file_size": 0,
  "receiver_id": 20
}
```

For video: `"__CALL__|video|<localCallId>"`.

**201 session brief:**

```json
{
  "session_id": "a1b2c3d4e5f67890",
  "status": "...",
  "file_name": "...",
  "file_size": 0,
  "sender_name": "...",
  "receiver_name": "...",
  "created_at": "...",
  "expires_in_seconds": 300,
  "ws_url": "/ws/p2p/a1b2c3d4e5f67890/"
}
```

`session_id` is **16 hex chars**. Use it as `call_id` everywhere after create.

### Step C — Caller sends invite chat token

```http
POST /api/chat/send/
```

```json
{
  "receiver_id": 20,
  "message": "__AIMS_CALL__|<session_id>|audio|<caller_user_id>"
}
```

Video: `__AIMS_CALL__|<session_id>|video|<caller_user_id>`

Also emit on chat WS:

```json
{
  "type": "call_invite",
  "call_id": "<session_id>",
  "callee_id": 20,
  "call_type": "audio"
}
```

Backend may also send FCM `call_invite` push.

### Step D — Callee accepts

```http
POST /api/p2p/session/join/
{ "session_id": "<session_id>" }
```

Then send control message:

```text
__AIMS_CALL_ACCEPT__|<session_id>
```

via `POST /api/chat/send/` to caller, and WS:

```json
{ "type": "call_accept", "call_id": "<session_id>", "caller_id": <caller> }
```

### Step E — Reject / hangup tokens

| Action | Chat message text |
|--------|-------------------|
| Reject | `__AIMS_CALL_REJECT__|<session_id>` |
| End | `__AIMS_CALL_END__|<session_id>` |

Hide these control messages in the chat UI (Flutter does).

### Step F — WebRTC on P2P socket

```text
WSS /ws/p2p/<session_id>/?token=<JWT>
```

| Direction | `type` | Payload |
|-----------|--------|---------|
| → server | `offer` / `answer` | `{ "sdp": "..." }` |
| → server | `ice_candidate` | `{ "candidate": {...} }` |
| → server | `hello` | `{ "platform": "web" }` |
| ← server | `connected`, `peer_joined`, `peer_left`, `role`, `offer`, `answer`, `ice_candidate`, `room_full` | |

Mute is **local** (no API). Ring timeout Flutter uses ~45s.

### Optional HTTP call-signal fallback

```http
POST /api/chat/call-signal/
POST /api/p2p/call-signal/          # alias
GET  /api/chat/call-signals/pending/
GET  /api/p2p/call-signals/pending/ # alias
```

Body `type` one of: `call_invite | call_accept | call_reject | call_hangup | call_dismiss | call_offer | call_answer | call_ice`  
Flutter live path prefers **WS + chat tokens**; keep HTTP as fallback if needed.

---

## 15. P2P file transfer (from chat attachment)

Same P2P APIs as calls, but real file metadata:

```http
POST /api/p2p/session/create/
{
  "file_name": "report.pdf",
  "file_size": 1234567,
  "receiver_id": 20
}
```

```http
POST /api/p2p/session/join/
{ "session_id": "..." }
```

```http
GET    /api/p2p/session/<session_id>/
DELETE /api/p2p/session/<session_id>/   # cancel → { "status": "cancelled" }
```

Then `/ws/p2p/<session_id>/` for WebRTC datachannel transfer (`file_info`, `transfer_complete`, etc.).

---

## 16. Notifications / push (chat-related)

| Method | Path | Notes |
|--------|------|--------|
| `GET` | `/api/notifications/` | list |
| `GET` | `/api/notifications/unread-count/` | `{ "unread_count": N }` |
| `POST` | `/api/notifications/<id>/` | `{ "action": "mark_read" }` |
| `POST` | `/api/notifications/mark-all-read/` | |
| `DELETE` | `/api/notifications/clear/` | |
| `POST` | `/api/devices/push/register/` | `{ "token": "...", "platform": "android"\|"ios" }` |
| `POST`/`DELETE` | `/api/devices/push/unregister/` | `{ "token": "..." }` |

Chat pushes also arrive as WS `notification` with `notification_type` like `new_message`, `new_group_message`, `call_invite`.

---

## 17. E2EE endpoints (backend ready; Flutter chat UI does not use yet)

| Method | Path |
|--------|------|
| `GET`/`PUT` | `/api/chat/e2ee/identity/` |
| `GET` | `/api/chat/e2ee/users/<user_id>/public-key/` |
| `GET`/`PUT` | `/api/chat/e2ee/direct-session/<other_user_id>/` |
| `GET`/`PUT` | `/api/chat/e2ee/group-session/<group_id>/` |

Skip unless product asks for encrypted chat.

---

## 18. Local-only features (no backend API)

| Feature | Notes |
|---------|--------|
| Pin / unpin chats | Flutter SharedPreferences |
| Chat wallpaper | local prefs |
| In-call mute | local WebRTC track |
| Block user | **not implemented** |
| Message search API | **none** (client-side filter only) |
| Group edit/delete message | **no REST** |

---

## 19. Quick reference — feature → API

| WhatsApp-like feature | API |
|----------------------|-----|
| Chat list | `GET /api/chat/users/` + `GET /api/chat/groups/` |
| Open DM | `GET /api/chat/conversation/<id>/` |
| Send / reply | `POST /api/chat/send/` + `reply_to_id` |
| Photo / file / voice | multipart on same send URL |
| Edit / delete | `PATCH` / `DELETE /api/chat/messages/<id>/` |
| React | `POST .../reactions/` `{ emoji }` |
| Blue ticks | `POST /api/chat/mark-read/` + WS `messages_read` |
| Typing | WS `typing` / `group_typing` |
| Online | WS `user_status` |
| Groups | `/api/chat/groups/...` |
| Audio call | P2P create + `__AIMS_CALL__|...|audio|...` + `/ws/p2p/` |
| Video call | same with `video` |
| File P2P | `/api/p2p/session/*` + `/ws/p2p/` |
| Live hub | `WSS /ws/chat/?token=` |

---

## 20. Minimal smoke test checklist for frontend

1. Login → save `access`  
2. `GET /api/chat/users/` → list renders  
3. Open user → `GET .../conversation/<id>/` → messages  
4. Send text → appear for both users via WS  
5. Send with `reply_to_id` → quote preview shows  
6. React with `👍` → both UIs update via WS `message_reaction`  
7. Type → peer sees typing indicator  
8. Open thread → peer gets `messages_read`  
9. Start audio call → callee rings → accept → media flows  
10. Start video call → camera tracks  
11. Create group → send group message + reaction  

---

## 21. Code pointers (for engineers)

| Area | Path |
|------|------|
| Flutter chat UI | `lib/pages/chat_page.dart` |
| Flutter API client | `lib/services/api_service.dart` |
| Call logic | `lib/services/call_service.dart`, `call_tokens.dart` |
| P2P files | `lib/services/chat_p2p_file_service.dart` |
| URL constants | `lib/config.dart` |
| Django routes | `screen/screenshots/api/urls.py` |
| Views | `screen/screenshots/api/views.py`, `p2p_views.py` |
| Reactions | `screen/screenshots/chat_reactions.py` |
| Call tokens | `screen/screenshots/call_tokens.py` |
| WS | `screen/screenshots/consumers.py`, `p2p_consumer.py`, `routing.py` |

---

*Generated for frontend handoff from Flutter + Django chat implementation. Ask backend/Flutter owners before changing token formats or reaction emoji allow-list.*

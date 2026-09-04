# HITL Dashboard Interaction Reference
### NBP WebGL — Angular ↔ Unity ↔ LiveKit

> **HITL** = Human-In-The-Loop. This document explains how the Angular dashboard
> communicates with the Unity WebGL scene, how video calls are started and ended,
> how the heartbeat polling works, and which APIs are called for each feature.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [How a Session Starts](#2-how-a-session-starts)
3. [How a Video Call Starts](#3-how-a-video-call-starts)
4. [How a Video Call Ends](#4-how-a-video-call-ends)
5. [Heartbeat Polling — Events & Logic](#5-heartbeat-polling--events--logic)
6. [API Reference — All Endpoints](#6-api-reference--all-endpoints)
7. [Angular ↔ Unity Message Bridge](#7-angular--unity-message-bridge)
8. [Feature Workflows](#8-feature-workflows)
9. [WebSocket Channel](#9-websocket-channel)
10. [Idle Session Timeout](#10-idle-session-timeout)

---

## 1. Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    Browser (Angular)                    │
│                                                         │
│  ┌──────────────┐   sendMessage()   ┌───────────────┐  │
│  │  Unity WebGL │ ◄───────────────► │  UnityComponent│  │
│  │   (canvas)   │   window.send     │  (Angular)    │  │
│  └──────────────┘   Message()       └───────┬───────┘  │
│                                             │           │
│                              ┌──────────────┼──────┐   │
│                              │              │      │   │
│                         WebSocket      REST APIs   │   │
│                         (wsUrl)        (fetch)     │   │
│                              │              │      │   │
└──────────────────────────────┼──────────────┼──────┘   │
                               │              │
                    ┌──────────▼──┐   ┌───────▼──────────┐
                    │  Form/WS    │   │  LiveKit Cloud    │
                    │  Server     │   │  (video call)     │
                    └─────────────┘   └──────────────────┘
```

**Two communication channels exist:**

| Channel | Direction | Purpose |
|---|---|---|
| `window.sendMessage(msg)` | Unity → Angular | Unity tells Angular to do something (open form, start call, show popup, etc.) |
| `unityInstance.SendMessage(obj, method, param)` | Angular → Unity | Angular tells Unity what happened (form submitted, call ended, language selected, etc.) |
| WebSocket (`environment.wsUrl`) | Bidirectional | Real-time form field fill / verbal data relay |
| REST APIs (`fetch`) | Angular → Server | Live call request, heartbeat poll, token fetch, file upload |

---

## 2. How a Session Starts

When the Angular app loads, `ngAfterViewInit()` runs and kicks off the following sequence:

```
Browser loads Angular app
        │
        ▼
ngAfterViewInit() runs
        │
        ├─► idleTimer.start()          — starts 5-min inactivity watch
        ├─► connectWebSocket()         — opens WS to environment.wsUrl (auto-reconnects every 3s)
        ├─► registerIframeListener()   — listens for postMessage from login/form iframes
        │
        ▼
Unity .loader.js script injected into <body>
        │
        ▼
createUnityInstance() called
        │
        ├─► Progress bar updates (0% → 99%) shown on loader screen
        │
        ▼
Unity instance ready
        │
        ├─► unityBridge.registerCanvas()   — sets up keyboard ownership guard
        ├─► connectWebSocket()             — ensures WS is open
        └─► SendMessage('UnityAngularBridge', 'Initialise', { action: 'Initialise' })
                                           — Angular tells Unity it is ready
```

**Unity then takes over** — it drives the conversation, and Angular reacts to messages Unity sends via `window.sendMessage()`.

---

## 3. How a Video Call Starts

There are **two paths** to starting a video call:

### Path A — Unity triggers it (HITL flow)

Unity sends: `start video call: <sessionId>`

Angular receives this in `window.sendMessage()` and calls `startHeartbeatVideoCall(sessionId)`.

```
Unity sends "start video call: <sessionId>"
        │
        ▼
startHeartbeatVideoCall(sessionId)
        │
        ├─► videoCallActive = true
        ├─► callStatus = "Waiting for agent..."
        ├─► Unity canvas slides right (MoveUnityToRight)
        │
        ▼
Heartbeat polling starts (every 3 seconds, max 20 attempts)
POST https://kiya.bharatmeta.in/nodeserver/api/v1/session/heartbeat
        │
        ▼
Poll response checked for serverCommands[].type === "CALL_JOIN"
        │
        ├─► No CALL_JOIN yet → wait 3s → poll again
        │
        └─► CALL_JOIN found → extract roomName + roomUrl from payload
                │
                ▼
        POST https://kiyaversesit.kiya.ai/EventManager_E_API/api/Agora/getLiveKitToken
        (get a signed LiveKit access token for the room)
                │
                ▼
        joinLivekitRoom(serverUrl, token)
        — connects to wss://absaverse-nkwzsokx.livekit.cloud
        — enables mic + camera
        — attaches local video to side panel
        — attaches remote agent video to main area
        — callStatus cleared → live call is active
```

### Path B — User clicks the toolbar video button

User clicks the camera icon in the toolbar → `toggleVideoCall()` → `startLivekitCall()`

```
User clicks video button
        │
        ▼
startLivekitCall()
        │
        ▼
POST https://kiya.bharatmeta.in/nodeserver/api/v1/live-call/request
Body: { deviceId, callerName, branchLocation }
        │
        ▼
Response: { data: { roomName, roomUrl } }
        │
        ▼
POST https://kiyaversesit.kiya.ai/EventManager_E_API/api/Agora/getLiveKitToken
Body: { Apikey, ParticipantIdentity, RoomName, secret, sessionId, roomName }
        │
        ▼
joinLivekitRoom(roomUrl, token)
— same LiveKit join flow as Path A
```

---

## 4. How a Video Call Ends

A call can end in three ways:

### A — User clicks "End Call" button
```
User clicks End Call
        │
        ▼
toggleVideoCall() → endLivekitCall()
        │
        ├─► clearInterval(heartbeatInterval)   — stop polling
        ├─► livekitRoom.disconnect()            — disconnect from LiveKit
        ├─► videoCallActive = false
        ├─► Unity canvas slides back to center (MoveUnityToCenter)
        └─► SendMessage('UnityAngularBridge', 'SendToUnity', 'video call ended:')
```

### B — LiveKit server disconnects (agent hangs up / network drop)
```
RoomEvent.Disconnected fires
        │
        ├─► videoCallActive = false
        ├─► Unity canvas slides back to center
        └─► SendMessage('UnityAngularBridge', 'SendToUnity', 'video call ended:')
```

### C — Heartbeat times out (no agent available)
```
20 heartbeat attempts exhausted with no CALL_JOIN
        │
        ├─► callStatus = "Agent unavailable"
        └─► endLivekitCall() called after 2 seconds
```

---

## 5. Heartbeat Polling — Events & Logic

The heartbeat is used **only in Path A** (Unity-triggered HITL call). It polls the server to wait for an agent to accept the call.

**Endpoint:** `POST https://kiya.bharatmeta.in/nodeserver/api/v1/session/heartbeat`

**Request body:**
```json
{ "sessionId": "<sessionId from Unity>" }
```

**Poll settings:**

| Setting | Value |
|---|---|
| Interval | Every **3 seconds** |
| Max attempts | **20** (= 60 seconds total) |
| Timeout behaviour | Shows "Agent unavailable", ends call after 2s |

**What Angular looks for in the response:**

```
response.data.serverCommands[]  (or response.serverCommands[])
        │
        └─► Find item where type === "CALL_JOIN"
                │
                └─► Extract from payload:
                        roomUrl   (also checked as serverUrl / url / livekitUrl / wsUrl)
                        roomName  (also checked as room / name / roomId)
                        token     (fallback only — primary token comes from getLiveKitToken API)
```

**Flow diagram:**

```
Poll #1 → no CALL_JOIN → wait 3s
Poll #2 → no CALL_JOIN → wait 3s
...
Poll N  → CALL_JOIN found
        │
        ├─► Stop polling immediately
        ├─► Fetch LiveKit token
        └─► Connect to LiveKit room
```

---

## 6. API Reference — All Endpoints

### 6.1 Live Call Request
| | |
|---|---|
| **URL** | `POST https://kiya.bharatmeta.in/nodeserver/api/v1/live-call/request` |
| **Trigger** | User clicks the video call toolbar button |
| **Request body** | `{ deviceId: "DBU-9999", callerName: "Kiosk User", branchLocation: "Main Branch" }` |
| **Response used** | `data.roomName`, `data.roomUrl` |

---

### 6.2 Heartbeat Poll
| | |
|---|---|
| **URL** | `POST https://kiya.bharatmeta.in/nodeserver/api/v1/session/heartbeat` |
| **Trigger** | Every 3 seconds after Unity sends `start video call: <sessionId>` |
| **Request body** | `{ sessionId: "<id>" }` |
| **Response used** | `data.serverCommands[].type === "CALL_JOIN"` → extracts `roomName`, `roomUrl` |

---

### 6.3 Get LiveKit Token
| | |
|---|---|
| **URL** | `POST https://kiyaversesit.kiya.ai/EventManager_E_API/api/Agora/getLiveKitToken` |
| **Trigger** | After `roomName` is known (both Path A and Path B) |
| **Request body** | `{ Apikey, ParticipantIdentity: "Kiosk User", participantName: "Kiosk User", RoomName, secret, sessionId, roomName }` |
| **Response used** | `token` (also checked as `Token`, `accessToken`, `data.token`) |
| **LiveKit server** | `wss://absaverse-nkwzsokx.livekit.cloud` |

---

### 6.4 Document Upload
| | |
|---|---|
| **URL** | `POST https://kiyaversesit.kiya.ai:5001/upload` |
| **Trigger** | User clicks "Submit Document" in the upload panel |
| **Request body** | `multipart/form-data` — field `file` with the filename Unity requested |
| **On success** | Sends Unity: `Document Upload Successfull:https://kiyaversesit.kiya.ai/NBP_WEBGL/assets/<filename>` |
| **On failure** | Upload panel shows error state with retry button |

---

## 7. Angular ↔ Unity Message Bridge

### Unity → Angular (`window.sendMessage(msg)`)

These are messages Unity sends to Angular. Angular parses the string and acts accordingly.

| Message pattern | What Angular does |
|---|---|
| `callForm:<formId>` | Opens the dynamic form panel with the given form ID |
| `callForm:<JSON with formId + fields>` | Opens form and pre-fills fields from the JSON payload |
| `start video call: <sessionId>` | Starts heartbeat polling and initiates HITL video call |
| `show warning: <JSON>` | Shows the warning confirmation modal |
| `show popup: <JSON>` | Shows the account opening options popup |
| `Upload Document: <filename>` | Shows the document upload panel, expects a file for that name |
| `show logout button` | Makes the logout button visible in the toolbar |
| `show capture button` | Shows the camera capture button |
| `authToken: <token>` | Stores the latest auth token, forwards to login iframe if open |
| `callURL: <url>` | Opens the given URL in the login iframe panel |
| `Journey Started` | Sets `journeyActive = true`, shows Cancel button |
| `Journey Ended` | Sets `journeyActive = false`, hides upload/cancel UI |
| `MoveUnityToRight` | Slides Unity canvas right (form panel opens on left) |
| `MoveUnityToCenter` | Slides Unity canvas back to center, closes form panel |
| `hide close button` | Hides the Cancel Flow button |
| `<JSON with form field keys>` | Verbal fill — patches matching fields in the open form |

---

### Angular → Unity (`unityInstance.SendMessage(gameObject, method, param)`)

These are messages Angular sends back to Unity.

| Game Object | Method | Param | When sent |
|---|---|---|---|
| `UnityAngularBridge` | `Initialise` | `{ action: 'Initialise' }` | Unity finishes loading |
| `UnityAngularBridge` | `MoveUnityToRight` | `""` | Form/login panel opens |
| `UnityAngularBridge` | `MoveUnityToCenter` | `""` | Form/login panel closes |
| `UnityAngularBridge` | `SendToUnity` | `"Submitted Form URL : <data>"` | User submits a dynamic form |
| `UnityAngularBridge` | `SendToUnity` | `"video call ended:"` | Video call disconnects |
| `UnityAngularBridge` | `SendToUnity` | `"Language Selected: <label>"` | User picks a language |
| `UnityAngularBridge` | `SendToUnity` | `"Avatar Selected: Avatar <index>"` | User picks an avatar |
| `UnityAngularBridge` | `SendToUnity` | `"workflow started: <flowName>"` | User clicks a service card |
| `UnityAngularBridge` | `SendToUnity` | `"cancel flow selected: <flowName>"` | User clicks Cancel Flow |
| `UnityAngularBridge` | `SendToUnity` | `"warningselected: <functionName>"` | User picks Yes/No on warning modal |
| `UnityAngularBridge` | `SendToUnity` | `"PopupSelected: <functionName>"` | User picks an option in popup menu |
| `UnityAngularBridge` | `SendToUnity` | `"logout clicked:"` | User clicks Logout |
| `UnityAngularBridge` | `SendToUnity` | `"capture image clicked:"` | User clicks Capture button |
| `UnityAngularBridge` | `SendToUnity` | `"Document Upload Successfull:<serverPath>"` | File uploaded successfully |
| `UnityAngularBridge` | `SendToUnity` | `<any WS message>` | WebSocket message relayed to Unity |
| `KeyboardManager` | `StartMic` | `""` | User holds Ctrl+Space |
| `KeyboardManager` | `StopMic` | `""` | User releases Ctrl+Space |
| `KeyboardManager` | `DisableKeyboardCapture` | `""` | Form input focused |
| `KeyboardManager` | `EnableKeyboardCapture` | `""` | Form input blurred |

---

## 8. Feature Workflows

### 8.1 Document Upload Flow

```
Unity sends: "Upload Document: <filename>"
        │
        ▼
Angular shows upload panel (drag & drop or file picker)
        │
        ▼
User selects file → preview shown
        │
        ▼
User clicks "Submit Document"
        │
        ▼
POST https://kiyaversesit.kiya.ai:5001/upload
(multipart/form-data, field name = filename Unity requested)
        │
        ├─► Success → SendMessage Unity:
        │   "Document Upload Successfull:https://kiyaversesit.kiya.ai/NBP_WEBGL/assets/<filename>"
        │   Panel auto-closes after 3 seconds
        │
        └─► Failure → Error state shown, user can retry
```

---

### 8.2 Dynamic Form Flow (callForm)

```
Unity sends: "callForm:<formId>"  OR  "callForm:<JSON>"
        │
        ▼
Angular extracts formId (and optional field pre-fill data)
        │
        ▼
Unity canvas slides right, form panel slides in from left
<app-dynamic-ui [formId]="..."> renders the form
        │
        ▼
If JSON payload had extra fields → patchFields() pre-fills them
        │
        ▼
User fills and submits the form
        │
        ▼
SendMessage Unity: "Submitted Form URL : <data>"
        │
        ▼
Unity sends "MoveUnityToCenter" → form panel closes
```

---

### 8.3 Service Flow (CJC Carousel)

```
User clicks toolbar Services button
        │
        ▼
Carousel shows: Fund Transfer | New Account | Balance Enquiry | Pay Bills
        │
        ▼
User clicks a service card
        │
        ▼
SendMessage Unity: "workflow started: <flowName>"
        │
        ▼
Unity starts the banking journey
        │
        ▼
Unity sends "Journey Started" → Cancel button appears
        │
        ▼
Journey runs (forms, uploads, confirmations...)
        │
        ▼
Unity sends "Journey Ended" → Cancel button hidden, UI resets
```

---

### 8.4 Login / URL Flow

```
Unity sends: "callURL: <url>"
        │
        ▼
Angular opens the URL in an iframe (left panel)
Unity canvas slides right
        │
        ▼
Angular sends current authToken to iframe via postMessage
        │
        ▼
Iframe completes login → postMessage back to Angular
        │
        ▼
Angular detects login success pattern in message
        │
        ▼
SendMessage Unity: <login result>
Iframe panel closes, Unity canvas returns to center
```

---

### 8.5 Language Selection

```
User clicks Language button in toolbar
        │
        ▼
Language modal opens (English, Hindi, Marathi, Tamil, Telugu)
        │
        ▼
User picks a language
        │
        ▼
SendMessage Unity: "Language Selected: <label>"
Modal closes
```

---

### 8.6 Avatar Selection

```
User clicks Avatar button in toolbar
        │
        ▼
Avatar modal opens (ANNA, DISHA, KIYA)
        │
        ▼
User picks an avatar
        │
        ▼
SendMessage Unity: "Avatar Selected: Avatar <index>"
Modal closes
```

---

### 8.7 Mic Shortcut (Push-to-Talk)

```
User holds Ctrl + Space
        │
        ▼
Angular claims keyboard ownership (away from Unity)
SendMessage KeyboardManager: "StartMic"
        │
        ▼
User releases Space
        │
        ▼
SendMessage KeyboardManager: "StopMic"
Keyboard ownership returned to Unity
```

---

## 9. WebSocket Channel

| Property | Value |
|---|---|
| URL | `environment.wsUrl` (configured per environment) |
| Auto-reconnect | Yes — retries every **3 seconds** on disconnect |
| Direction | Bidirectional |

**Incoming messages (server → Angular):**
- If the message contains keys matching the currently open form's fields → Angular calls `patchFields()` to fill the form (verbal fill / AI-driven field population)
- Otherwise → relayed directly to Unity via `SendMessage('UnityAngularBridge', 'SendToUnity', msg)`

**Outgoing messages (Angular → server):**
- When a form loads: `{ action: 'formLoaded', formId: '<id>' }`
- Any message Unity asks Angular to forward via `window.sendToFormServer(msg)`

---

## 10. Idle Session Timeout

| Setting | Value |
|---|---|
| Idle threshold | **5 minutes** of no activity |
| Warning countdown | **2 minutes** |
| Activity events monitored | `mousemove`, `mousedown`, `keydown`, `scroll`, `touchstart`, `wheel` |
| On countdown reaching zero | `window.location.reload()` — full page refresh |

**Flow:**

```
No user activity for 5 minutes
        │
        ▼
Full-screen blur overlay appears
Countdown timer starts at 2:00 and counts down
        │
        ├─► User clicks "I'm still here" or moves mouse / presses key
        │           │
        │           └─► Overlay dismissed, idle timer resets to 5 minutes
        │
        └─► Countdown reaches 0:00
                    │
                    └─► window.location.reload()
```

---

## Quick Reference — Who Calls What

| Feature | Initiated by | API / Method called |
|---|---|---|
| App load | Browser | `createUnityInstance()`, `connectWebSocket()` |
| Video call (user) | User clicks toolbar | `POST /live-call/request` → `POST /getLiveKitToken` → LiveKit |
| Video call (HITL) | Unity message | `POST /session/heartbeat` (poll) → `POST /getLiveKitToken` → LiveKit |
| End call | User or LiveKit event | `livekitRoom.disconnect()` |
| Document upload | Unity message + user | `POST https://kiyaversesit.kiya.ai:5001/upload` |
| Open form | Unity message | Internal — renders `<app-dynamic-ui>` |
| Verbal field fill | WebSocket message | Internal — `patchFields()` |
| Language change | User clicks toolbar | `SendMessage` to Unity only |
| Avatar change | User clicks toolbar | `SendMessage` to Unity only |
| Service flow | User clicks card | `SendMessage` to Unity only |
| Idle timeout | Timer | `window.location.reload()` |

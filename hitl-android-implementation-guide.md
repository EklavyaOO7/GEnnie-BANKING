# HITL LiveKit — Android App Implementation Guide

This guide explains how to port the **Human-In-The-Loop (HITL) session + LiveKit video call** feature
from the DBU Unity kiosk into an Android app. The Unity side is the reference implementation —
every class, payload shape, and event name here is taken directly from it.

---

## 1. How the System Works (Unity Reference)

```
Customer presses "Call Agent"
        │
        ▼
HitlKioskFunctions.StartHitlSession()
  ├─ HITLSessionService.MarkHumanInterventionRequired()
  ├─ Sends hitl_start heartbeat  ──────────────────────────► Dashboard backend
  │     payload: { event, journeyName, workflowId, session, state }
  │
  ▼
Dashboard assigns agent → sends AGENT_ASSIGNED command
  ▼
Dashboard initiates call → sends CALL_REQUEST + CALL_JOIN commands
  ▼
HitlCallHandler receives CALL_JOIN → calls LiveCallManager.JoinInbound()
  ▼
LiveKit room connected → agent video appears
  ▼
Agent sends APPROVED / REJECTED command
  ▼
HitlKioskFunctions.AdvanceCJC() → ends session, advances journey
  ▼
hitl_end heartbeat sent ────────────────────────────────────► Dashboard backend
```

---

## 2. Packages / SDKs Required

| Package | Purpose | Android equivalent |
|---|---|---|
| `ai.kiya.liveconnection` | Heartbeat WebSocket to dashboard | Retrofit + OkHttp WebSocket |
| `ai.kiya.livecall` (LiveKit) | WebRTC video call | `io.livekit:livekit-android` |
| `Newtonsoft.Json` | JSON serialization | Gson / Moshi |

### Gradle dependencies
```gradle
// LiveKit Android SDK
implementation 'io.livekit:livekit-android:2.x.x'

// WebSocket (heartbeat)
implementation 'com.squareup.okhttp3:okhttp:4.x.x'

// JSON
implementation 'com.google.code.gson:gson:2.x.x'
```

---

## 3. AppConfig Keys Required

These keys must be present in your remote AppConfig JSON (same as Unity):

| Key | Description |
|---|---|
| `LIVEKIT_API_KEY` | LiveKit server API key |
| `LIVEKIT_API_SECRET` | LiveKit server API secret |
| `LIVEKIT_ROOM_URL` | `wss://your-livekit-server.com` |
| `Channeltype` | e.g. `"GenAI"` — stamped into session payload |
| `HitlAgentTimeoutSeconds` | Seconds to wait for agent before auto-cancel (default 30) |
| `hitlEventSpeech` | JSON object with TTS strings per call event (optional) |
| `deviceId` | Device identifier sent in session identity |

---

## 4. Session State Payload Shape

`HITLSessionService.GetCurrentState()` produces this JSON — your Android app must send the
**exact same shape** in the `hitl_start` heartbeat:

```json
{
  "session": {
    "sessionId": "SESS-a1b2c3d4",
    "channel": "GenAI",
    "journeyName": "New Account",
    "workflowId": "WF-NEW-ACCOUNT",
    "currentStage": "PROCESSING",
    "humanInterventionRequired": false,
    "priority": "NORMAL",
    "currentNodeId": "ContactDetails_13120",
    "meta": {
      "sourceSystem": "GenAI",
      "tenant": "BankName",
      "groupOffice": "Main Branch"
    }
  },
  "runtime": {
    "executionMode": "LIVE",
    "nodeStates": {
      "MOAccountDetails_13103": {
        "nodeType": "FORM",
        "status": "COMPLETED",
        "renderer": {
          "renderType": "URL",
          "url": "https://...param?{...submitted form data...}",
          "emptyFormUrl": "https://...param?{\"formId\":\"1465\"}"
        }
      },
      "NODE_NEW_ACCOUNT_2": {
        "nodeType": "DOCUMENT",
        "status": "COMPLETED",
        "renderer": {
          "renderType": "BASE64",
          "url": "https://blob.storage.../image.png"
        }
      }
    },
    "visitedNodes": ["MOAccountDetails_13103", "ContactDetails_13120", "NODE_NEW_ACCOUNT_2"],
    "currentExecutionPointer": "NODE_NEW_ACCOUNT_2"
  },
  "audit": {
    "createdBy": "NBP",
    "lastModifiedBy": "GENIE"
  }
}
```

### Session ID generation
```kotlin
fun generateSessionId(): String = "SESS-${UUID.randomUUID().toString().replace("-","").take(8)}"
```

### Workflow ID generation
```kotlin
fun buildWorkflowId(journeyName: String): String =
    "WF-" + journeyName.trim().uppercase().replace(" ", "-").replace("_", "-")
```

---

## 5. Heartbeat Protocol

The heartbeat is a **polling HTTP POST** (not a persistent WebSocket) to the session endpoint.
The Unity `HeartbeatConnection` sends a JSON body every N seconds.

### Session start endpoint
```
POST https://kiya.bharatmeta.in/nodeserver/api/v1/session/start
Content-Type: application/json

{
  "deviceId": "DEVICE-001",
  "appVersion": "1.0.0",
  "deviceType": "KIOSK",
  "branch": "main",
  "buildNumber": "",
  "environment": "production"
}
```

### Heartbeat body (sent every 2 seconds while HITL is active)
The heartbeat body is built incrementally by calling `heartbeat.Send(key, value)`.
For `hitl_start` the full body is:

```json
{
  "event": "hitl_start",
  "journeyName": "New Account",
  "workflowId": "WF-NEW-ACCOUNT",
  "session": { /* GetSessionIdentity() result — see §4 */ },
  "state":   { /* GetCurrentState() result — see §4 */ }
}
```

For `hitl_end`:
```json
{
  "event": "hitl_end",
  "reason": "HITL_COMPLETE"
}
```

Possible `reason` values: `HITL_COMPLETE`, `SESSION_RESET`, `FLOW_ENDED`

### Session identity object (sent as `session` key in hitl_start)
```json
{
  "sessionId": "SESS-a1b2c3d4",
  "journeyName": "New Account",
  "workflowId": "WF-NEW-ACCOUNT",
  "channel": "GenAI",
  "tenant": "BankName",
  "groupOffice": "Main Branch",
  "deviceId": "DEVICE-001",
  "deviceName": "DBU-Kiosk-01"
}
```

---

## 6. Inbound Server Commands

The server sends commands back via the heartbeat response. Each command has this shape:

```json
{
  "commandId": "cmd-uuid-here",
  "type": "AGENT_ASSIGNED",
  "payload": {
    "agentName": "Priya Sharma"
  }
}
```

### Commands your Android app must handle

| `type` | Payload keys | Action |
|---|---|---|
| `AGENT_ASSIGNED` | `agentName` | Show "Agent assigned" UI |
| `CALL_REQUEST` | `callId`, `fromName` | Show incoming call UI |
| `CALL_JOIN` | `callId`, `roomName`, `token`, `roomUrl` | Join LiveKit room |
| `CALL_END` | `callId` | End LiveKit call |
| `APPROVED` | — | Advance journey with result = "APPROVED" |
| `REJECTED` | — | Advance journey with result = "REJECTED" |
| `SEND_FORM` | `formUrl` | Open WebView with form URL |
| `FORM_URL_RESPONSE` | `formUrl` | Open WebView with form URL |
| `SEND_SCAN` | `deviceType` | Trigger device scan (camera, biometric, etc.) |

**Deduplication:** The server replays all unacknowledged commands on every heartbeat tick.
Store processed `commandId` values in a `HashSet<String>` and skip duplicates.

---

## 7. LiveKit Integration (Android)

### 7.1 Token generation
The Unity app generates its **own** token using `LIVEKIT_API_KEY` + `LIVEKIT_API_SECRET` —
it does NOT use the token sent in `CALL_JOIN`. Do the same on Android to avoid clock-skew issues.

```kotlin
// Use LiveKit server SDK or your backend to generate a token
// Identity: your deviceId (e.g. "DBU-101")
// Room: _pendingRoomName from CALL_JOIN payload
val token = LiveKitTokenGenerator.generate(
    apiKey    = appConfig["LIVEKIT_API_KEY"],
    apiSecret = appConfig["LIVEKIT_API_SECRET"],
    roomName  = pendingRoomName,
    identity  = deviceId
)
```

If token generation must happen server-side, call your backend with `roomName` + `deviceId`
and receive the token before calling `room.connect()`.

### 7.2 Connect to room
```kotlin
val room = Room()
room.connect(
    url   = appConfig["LIVEKIT_ROOM_URL"],   // wss://...
    token = token
)
```

### 7.3 Publish local camera + mic
```kotlin
val localParticipant = room.localParticipant
localParticipant.setCameraEnabled(true)
localParticipant.setMicrophoneEnabled(true)
```

### 7.4 Receive remote video
```kotlin
room.events.collect { event ->
    when (event) {
        is RoomEvent.TrackSubscribed -> {
            if (event.track is VideoTrack) {
                val videoTrack = event.track as VideoTrack
                videoTrack.addRenderer(remoteVideoView)  // SurfaceViewRenderer
            }
        }
        is RoomEvent.ParticipantDisconnected -> {
            // Agent left — end call
            endCall()
        }
    }
}
```

### 7.5 End call
```kotlin
fun endCall() {
    room.localParticipant.setCameraEnabled(false)
    room.localParticipant.setMicrophoneEnabled(false)
    room.disconnect()
    sendHitlEnd("HITL_COMPLETE")
}
```

---

## 8. Node State Recording

Before the agent call, record every form submission and image capture as nodes.
These are accumulated and sent in the `hitl_start` heartbeat.

### Record a form submission
```kotlin
// Called when user submits a form (equivalent of HITLSessionService.OnFormDataReceived)
fun recordFormNode(nodeId: String, filledUrl: String, emptyFormUrl: String) {
    nodeStates[nodeId] = NodeState(
        nodeType = "FORM",
        status   = "COMPLETED",
        renderer = Renderer(renderType = "URL", url = filledUrl, emptyFormUrl = emptyFormUrl)
    )
    visitedNodes.add(nodeId)
    currentNodeId = nodeId
}
```

### Record an image/document
```kotlin
// Called after image upload to Azure Blob (equivalent of HITLSessionService.OnImageCaptured)
fun recordDocumentNode(nodeId: String, blobUrl: String) {
    nodeStates[nodeId] = NodeState(
        nodeType = "DOCUMENT",
        status   = "COMPLETED",
        renderer = Renderer(renderType = "BASE64", url = blobUrl)
    )
    visitedNodes.add(nodeId)
    currentNodeId = nodeId
}
```

---

## 9. Full HITL Session Lifecycle (Android)

```
App start
  └─ POST /session/start  (DeviceMonitor equivalent)
  └─ Start polling heartbeat every 2s

User completes journey steps
  └─ recordFormNode() / recordDocumentNode() for each step

User taps "Call Agent"
  └─ HITLSession.markHumanInterventionRequired()
  └─ Send hitl_start heartbeat with full state
  └─ Start agent timeout timer (HitlAgentTimeoutSeconds)
  └─ Show "Connecting..." UI

Server → AGENT_ASSIGNED
  └─ Cancel timeout timer
  └─ Show "Agent assigned: {agentName}"

Server → CALL_REQUEST
  └─ Show incoming call panel (or auto-accept)

Server → CALL_JOIN
  └─ Generate LiveKit token
  └─ room.connect(roomUrl, token)
  └─ Show video call UI

LiveKit → agent video track received
  └─ Render agent video in SurfaceViewRenderer

Server → APPROVED or REJECTED
  └─ endCall()
  └─ Send hitl_end heartbeat (reason = "HITL_COMPLETE")
  └─ Advance journey with result variable = "APPROVED" / "REJECTED"

OR: Agent timeout fires
  └─ endCall()
  └─ Send hitl_end heartbeat (reason = "SESSION_RESET")
  └─ Show "Agent not available" message
  └─ Reset workflow

Session reset / new journey
  └─ Send hitl_end heartbeat (reason = "SESSION_RESET")
  └─ Clear all node states, visited nodes, session ID
```

---

## 10. Android Class Structure

Mirror the Unity class responsibilities:

| Unity class | Android equivalent |
|---|---|
| `HITLSessionService` | `HITLSessionManager` (singleton ViewModel or object) |
| `HitlKioskFunctions` | `HITLCallController` (orchestrates session + call) |
| `DeviceMonitor` | `DeviceHeartbeatService` (background service / coroutine) |
| `HitlCallHandler` | `HITLCommandHandler` (processes inbound server commands) |
| `LiveCallManager` | `LiveKitCallManager` (wraps LiveKit Room) |
| `HeartbeatConnection` | `HeartbeatClient` (OkHttp polling loop) |
| `LiveLinkMessageRouter` | `CommandRouter` (routes typed commands to handlers) |

---

## 11. Heartbeat Polling Implementation (Kotlin)

```kotlin
class HeartbeatClient(
    private val sessionUrl: String,
    private val intervalMs: Long = 2000L
) {
    private val client = OkHttpClient()
    private val pendingData = mutableMapOf<String, Any>()
    private var job: Job? = null

    fun send(key: String, value: Any) { pendingData[key] = value }

    fun start(scope: CoroutineScope) {
        job = scope.launch {
            while (isActive) {
                val body = Gson().toJson(pendingData.toMap())
                pendingData.clear()
                try {
                    val request = Request.Builder()
                        .url(sessionUrl)
                        .post(body.toRequestBody("application/json".toMediaType()))
                        .build()
                    val response = client.newCall(request).execute()
                    val responseBody = response.body?.string() ?: ""
                    if (responseBody.isNotEmpty()) onMessage(responseBody)
                } catch (e: Exception) {
                    Log.e("Heartbeat", "Error: ${e.message}")
                }
                delay(intervalMs)
            }
        }
    }

    fun stop() { job?.cancel() }

    var onMessage: (String) -> Unit = {}
}
```

---

## 12. Command Router Implementation (Kotlin)

```kotlin
data class ServerCommand(
    val commandId: String?,
    val type: String,
    val payload: Map<String, String> = emptyMap()
)

class CommandRouter {
    private val processedIds = mutableSetOf<String>()
    var onCommand: ((ServerCommand) -> Unit)? = null

    fun process(json: String) {
        val cmd = Gson().fromJson(json, ServerCommand::class.java) ?: return
        if (!cmd.commandId.isNullOrEmpty() && !processedIds.add(cmd.commandId)) return
        onCommand?.invoke(cmd)
    }

    fun clearProcessedIds() = processedIds.clear()
}
```

---

## 13. Scene / UI Components Needed

| Component | Description |
|---|---|
| `SurfaceViewRenderer` (remote) | Renders agent's video stream |
| `SurfaceViewRenderer` (local) | Renders device camera preview |
| Connecting panel | Shown while waiting for agent |
| In-call panel | Shown once agent joins LiveKit room |
| Mute mic button | Calls `localParticipant.setMicrophoneEnabled(false)` |
| End call button | Calls `endCall()` |
| Agent name label | Populated from `AGENT_ASSIGNED` payload |

---

## 14. Key Differences from Unity

| Unity | Android |
|---|---|
| `Helper.NewWorkFlowStart` event | Your journey navigation callback / ViewModel event |
| `Helper.ResetAllProcesses` event | App-level reset broadcast / ViewModel event |
| `Loader.Get().GetAppConfigValue()` | Your `AppConfig` singleton / SharedPreferences |
| `DLog.Log()` | `Log.d("TAG", message)` |
| `StartCoroutine()` | `lifecycleScope.launch {}` / `viewModelScope.launch {}` |
| `PlayerPrefs` | `SharedPreferences` |
| `FindFirstObjectByType<T>()` | Dependency injection (Hilt/Koin) or singleton access |
| `DontDestroyOnLoad` | Application-scoped singleton / retained ViewModel |

---

## 15. Anti-Patterns to Avoid

- **Do not** clear `processedIds` while a HITL session is active — the server replays commands
  on every heartbeat tick and you will get duplicate APPROVED/REJECTED handling.
- **Do not** generate a new session ID on every heartbeat — generate once on journey start and
  reuse until `endSession()`.
- **Do not** use the token from `CALL_JOIN` payload — generate your own with API key + secret
  to avoid `nbf` (not-before) clock-skew errors.
- **Do not** stop the heartbeat during the call — the server needs continuous heartbeats to
  deliver APPROVED/REJECTED commands.
- **Do not** call `endSession()` before sending the `hitl_end` heartbeat — send the heartbeat
  first, then clear state.

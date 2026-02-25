# Backend Specification

This document specifies the REST API requirements for the rpi-infodisplay controller backend, inspired by the UniFi controller adoption model.

## Overview

The rpi-infodisplay application is an Electron-based kiosk display client that runs on Raspberry Pi devices. It needs a central controller backend to:

1. **Register/adopt** new devices
2. **Configure** device settings remotely
3. **Monitor** device status and health
4. **Control** devices (refresh, screenshot, reboot, etc.)

## Architecture

```
┌─────────────────┐         ┌─────────────────┐
│  Raspberry Pi   │  HTTPS  │    Backend      │
│  (Electron App) │◄───────►│   Controller    │
└─────────────────┘         └─────────────────┘
        │                           │
        │ Displays webpage          │ Admin UI
        ▼                           ▼
┌─────────────────┐         ┌─────────────────┐
│   Display URL   │         │   Admin Panel   │
│   (any website) │         │                 │
└─────────────────┘         └─────────────────┘
```

## Device Identification

Each device is uniquely identified by:

| Field | Source | Example |
|-------|--------|---------|
| `serial` | OS serial number | `10000000abcd1234` |
| `mac` | Default network interface MAC | `dc:a6:32:xx:xx:xx` |
| `publicKey` | Device-generated Ed25519 key | `MCowBQYDK2VwAyEA...` |

## Security Model

### Why Cryptographic Authentication?

Serial numbers and MAC addresses can be spoofed. To prevent unauthorized devices from impersonating legitimate ones, we use **Ed25519 public-key cryptography**.

### How It Works

```
┌─────────────────────────────────────────────────────────────────┐
│                        FIRST BOOT                               │
├─────────────────────────────────────────────────────────────────┤
│  1. Device generates Ed25519 keypair                            │
│  2. Private key stored locally (~/.config/rpi-infodisplay/)     │
│  3. Public key sent with announce request                       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                        ADOPTION                                 │
├─────────────────────────────────────────────────────────────────┤
│  4. Admin adopts device in controller UI                        │
│  5. Backend stores public key with device record                │
│  6. Device receives deviceId (for API calls)                    │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    AUTHENTICATED REQUESTS                       │
├─────────────────────────────────────────────────────────────────┤
│  7. Device signs each request with private key                  │
│  8. Backend verifies signature with stored public key           │
│  9. Rejects requests with invalid/missing signatures            │
└─────────────────────────────────────────────────────────────────┘
```

### Key Storage (Device-side)

```
~/.config/rpi-infodisplay/
├── device.key          # Ed25519 private key (PEM format)
├── device.pub          # Ed25519 public key (PEM format)  
└── device-id           # UUID assigned by backend after adoption
```

If these files are deleted (e.g., SD card reflash), the device generates a new keypair and must be re-adopted. This is intentional - like UniFi behavior.

### Request Signing

All requests after announcement must include signature headers:

```http
POST /api/v1/devices/{id}/heartbeat
X-Device-Id: uuid-here
X-Timestamp: 2026-01-13T12:00:00.000Z
X-Signature: base64-encoded-signature
Content-Type: application/json

{ "uptime": 86400, "ip": "192.168.1.100" }
```

**Signature generation (device-side):**
```javascript
import { createSign } from 'crypto';

const signRequest = (privateKey, method, path, timestamp, body) => {
  const payload = `${method}\n${path}\n${timestamp}\n${JSON.stringify(body)}`;
  const sign = createSign('Ed25519');
  sign.update(payload);
  return sign.sign(privateKey, 'base64');
};
```

**Signature verification (backend-side):**
```javascript
import { createVerify } from 'crypto';

const verifyRequest = (publicKey, method, path, timestamp, body, signature) => {
  // Reject if timestamp is older than 5 minutes (prevents replay attacks)
  const age = Date.now() - new Date(timestamp).getTime();
  if (age > 5 * 60 * 1000) return false;
  
  const payload = `${method}\n${path}\n${timestamp}\n${JSON.stringify(body)}`;
  const verify = createVerify('Ed25519');
  verify.update(payload);
  return verify.verify(publicKey, signature, 'base64');
};
```

### Security Benefits

| Threat | Protection |
|--------|------------|
| MAC/Serial spoofing | Attacker can't sign requests without private key |
| Man-in-the-middle | Requests are signed; tampering invalidates signature |
| Replay attacks | Timestamp in signature; backend rejects old requests |
| Stolen device | Remove from backend; old keys become useless |
| Compromised key | Re-adopt device; generates new keypair |

### Announce Request (Pre-adoption)

The only unsigned request is the initial announcement:

```http
POST /api/v1/devices/announce
Content-Type: application/json

{
  "serial": "10000000abcd1234",
  "publicKey": "-----BEGIN PUBLIC KEY-----\nMCowBQYDK2Vw...\n-----END PUBLIC KEY-----",
  "system": { ... },
  "config": { ... }
}
```

This is safe because:
1. Pending devices have no access until adopted
2. Admin verifies device identity before adoption (e.g., matching IP shown on display)
3. Public key is bound to device record upon adoption

## Device Data Model

### System Information (sent by device)

```json
{
  "serial": "10000000abcd1234",
  "system": {
    "cpu": {
      "manufacturer": "ARM",
      "brand": "Cortex-A76",
      "vendor": "ARM",
      "family": "8",
      "model": "0",
      "revision": "4"
    },
    "osInfo": {
      "platform": "linux",
      "distro": "Debian GNU/Linux",
      "release": "12",
      "codename": "bookworm",
      "kernel": "6.6.31+rpt-rpi-2712",
      "arch": "arm64",
      "serial": "10000000abcd1234"
    },
    "system": {
      "manufacturer": "Raspberry Pi",
      "model": "Raspberry Pi 5 Model B Rev 1.0"
    },
    "defaultNetworkInterface": {
      "iface": "eth0",
      "ifaceName": "eth0",
      "ip4": "192.168.1.100",
      "mac": "dc:a6:32:xx:xx:xx",
      "type": "wired",
      "default": true
    }
  }
}
```

### Device Configuration (managed by backend)

```json
{
  "name": "lobby-display-01",
  "location": "Main Building Lobby",
  "url": "https://example.com/display",
  "fullscreen": true,
  "frame": false,
  "zoomFactor": 1.6
}
```

## Adoption Flow (UniFi-style)

### Sequence Diagram

```
DEVICE                                      BACKEND                         ADMIN
  │                                            │                              │
  │ 1. Boot & announce                         │                              │
  │ ──────────────────────────────────────────►│                              │
  │    POST /devices/announce                  │                              │
  │    {serial, publicKey, system}             │                              │
  │                                            │                              │
  │ ◄──────────────────────────────────────────│                              │
  │    {status: "pending", deviceId: "xxx"}    │                              │
  │                                            │                              │
  │ 2. Store deviceId, start polling           │                              │
  │                                            │                              │
  │ 3. Poll (repeats every 30-60s)             │  4. View pending devices     │
  │ ──────────────────────────────────────────►│◄─────────────────────────────│
  │    GET /devices/xxx/poll                   │    GET /devices?status=pending
  │                                            │                              │
  │ ◄──────────────────────────────────────────│                              │
  │    {status: "pending"}                     │                              │
  │                                            │                              │
  │         ... device keeps polling ...       │  5. Adopt device             │
  │                                            │◄─────────────────────────────│
  │                                            │    POST /devices/xxx/adopt   │
  │                                            │    {name, location, url}     │
  │                                            │                              │
  │ 6. Poll receives adoption                  │                              │
  │ ──────────────────────────────────────────►│                              │
  │    GET /devices/xxx/poll                   │                              │
  │                                            │                              │
  │ ◄──────────────────────────────────────────│                              │
  │    {status: "adopted", config: {...}}      │                              │
  │                                            │                              │
  │ 7. Apply config, load URL                  │                              │
  │                                            │                              │
  │ 8. Start heartbeats                        │                              │
  │ ──────────────────────────────────────────►│                              │
  │    POST /devices/xxx/heartbeat             │                              │
  │                                            │                              │
```

### Device Behavior

1. **On boot:** Announce to controller, receive `deviceId`
2. **If pending:** Poll every 30-60 seconds waiting for adoption
3. **If adopted:** Apply config, load URL, start sending heartbeats
4. **Ongoing:** Continue polling for config changes and commands

### 1. Device Discovery

When a device starts, it announces itself to the controller:

```
POST /api/v1/devices/announce
```

**Request Body:**
```json
{
  "serial": "10000000abcd1234",
  "publicKey": "-----BEGIN PUBLIC KEY-----\nMCowBQYDK2VwAyEA...\n-----END PUBLIC KEY-----",
  "system": { ... },
  "config": {
    "name": "",
    "location": "",
    "url": "https://edugo.be",
    "zoomFactor": 1
  }
}
```

**Response (device not adopted):**
```json
{
  "status": "pending",
  "message": "Device pending adoption",
  "deviceId": "uuid-here"
}
```

**Response (device adopted):**
```json
{
  "status": "adopted",
  "deviceId": "uuid-here",
  "config": {
    "name": "lobby-display-01",
    "location": "Main Building Lobby",
    "url": "https://example.com/display",
    "zoomFactor": 1.6
  }
}
```

### 2. Admin Adopts Device

Admin sees pending devices in the controller UI and adopts them:

```
POST /api/v1/devices/{deviceId}/adopt
```

**Request Body:**
```json
{
  "name": "lobby-display-01",
  "location": "Main Building Lobby",
  "url": "https://example.com/display",
  "zoomFactor": 1.6
}
```

### 3. Device Polls for Updates

Devices periodically poll for configuration changes and commands:

```
GET /api/v1/devices/{deviceId}/poll
X-Device-Id: {deviceId}
X-Timestamp: 2026-01-13T12:00:00.000Z
X-Signature: {signature}
```

**Response:**
```json
{
  "configChanged": true,
  "config": { ... },
  "pendingCommands": [
    {
      "id": "cmd-uuid",
      "action": "refresh",
      "payload": {}
    }
  ]
}
```

## API Endpoints

### Device Endpoints (called by devices)

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/api/v1/devices/announce` | Register/announce device to controller |
| `GET` | `/api/v1/devices/{id}/poll` | Poll for config updates and commands |
| `POST` | `/api/v1/devices/{id}/heartbeat` | Send heartbeat with status |
| `POST` | `/api/v1/devices/{id}/commands/{cmdId}/ack` | Acknowledge command execution |
| `POST` | `/api/v1/devices/{id}/screenshot` | Upload screenshot (multipart) |

### Admin Endpoints (called by admin UI)

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/v1/devices` | List all devices |
| `GET` | `/api/v1/devices/{id}` | Get device details |
| `POST` | `/api/v1/devices/{id}/adopt` | Adopt a pending device |
| `PUT` | `/api/v1/devices/{id}` | Update device configuration |
| `DELETE` | `/api/v1/devices/{id}` | Remove/forget device |
| `POST` | `/api/v1/devices/{id}/commands` | Send command to device |
| `GET` | `/api/v1/devices/{id}/screenshot` | Get latest screenshot |

## Commands

Commands are queued on the backend and picked up by devices during polling.

| Command | Payload | Description |
|---------|---------|-------------|
| `refresh` | `{}` | Reload the current webpage |
| `navigate` | `{ "url": "..." }` | Navigate to a new URL |
| `updateConfig` | `{ "name": "...", ... }` | Update device configuration |
| `screenshot` | `{}` | Request screenshot upload |
| `reboot` | `{}` | Reboot the device |
| `identify` | `{}` | Show info overlay (flash IP) |

## Heartbeat

Devices send periodic heartbeats to indicate they're online:

```
POST /api/v1/devices/{id}/heartbeat
```

**Request Body:**
```json
{
  "timestamp": "2026-01-13T12:00:00Z",
  "uptime": 86400,
  "currentUrl": "https://example.com/display",
  "ip": "192.168.1.100"
}
```

**Recommended interval:** 60 seconds

## Device States

| State | Description |
|-------|-------------|
| `pending` | Device announced but not yet adopted |
| `adopted` | Device adopted and configured |
| `online` | Device is sending heartbeats |
| `offline` | No heartbeat received (threshold: 3 minutes) |
| `stale` | No heartbeat for extended period (threshold: 7 days) |
| `updating` | Device is applying new configuration |

## Device Lifecycle & Stale Device Management

### Timestamps Tracked

The backend should track these timestamps for each device:

| Field | Updated When | Purpose |
|-------|--------------|---------|
| `createdAt` | Device first announces | Track device age |
| `adoptedAt` | Admin adopts device | Track adoption date |
| `lastSeenAt` | Every heartbeat/poll | Detect offline/stale devices |
| `lastConfigChangeAt` | Config is modified | Track configuration changes |

### State Transitions

```
┌──────────┐     announce      ┌──────────┐      adopt       ┌──────────┐
│  (new)   │ ────────────────► │ pending  │ ───────────────► │ adopted  │
└──────────┘                   └──────────┘                  └──────────┘
                                    │                             │
                                    │ no adopt                    │ heartbeat
                                    │ (7 days)                    ▼
                                    │                        ┌──────────┐
                                    │                        │  online  │◄─────┐
                                    ▼                        └──────────┘      │
                               ┌──────────┐                       │            │
                               │  stale   │                       │ no heartbeat
                               │ (pending)│                       │ (3 min)
                               └──────────┘                       ▼            │
                                    │                        ┌──────────┐      │
                                    │                        │ offline  │──────┘
                                    ▼                        └──────────┘  heartbeat
                               ┌──────────┐                       │
                               │ cleanup  │                       │ no heartbeat
                               │ (delete) │                       │ (7 days)
                               └──────────┘                       ▼
                                                             ┌──────────┐
                                                             │  stale   │
                                                             │(adopted) │
                                                             └──────────┘
```

### Stale Device Thresholds

| Device State | Stale After | Recommended Action |
|--------------|-------------|-------------------|
| `pending` | 7 days | Auto-delete (never adopted) |
| `adopted` | 7 days offline | Flag for review |
| `adopted` | 30 days offline | Suggest removal |
| `adopted` | 90 days offline | Auto-archive or delete |

### Admin Endpoints for Stale Management

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/v1/devices?status=stale` | List stale devices |
| `GET` | `/api/v1/devices?lastSeenBefore={iso8601}` | Filter by last seen date |
| `DELETE` | `/api/v1/devices/{id}` | Remove device |
| `POST` | `/api/v1/devices/cleanup` | Bulk cleanup stale devices |

### Cleanup Endpoint

```
POST /api/v1/devices/cleanup
```

**Request Body:**
```json
{
  "olderThan": "2025-10-13T00:00:00Z",
  "status": ["pending", "stale"],
  "dryRun": true
}
```

**Response:**
```json
{
  "found": 12,
  "deleted": 0,
  "dryRun": true,
  "devices": [
    {
      "id": "uuid",
      "name": "unknown-device",
      "serial": "1000000abc",
      "lastSeenAt": "2025-09-01T12:00:00Z",
      "status": "stale"
    }
  ]
}
```

Set `dryRun: false` to actually delete the devices.

### Device Record Schema

```json
{
  "id": "uuid",
  "serial": "10000000abcd1234",
  "mac": "dc:a6:32:xx:xx:xx",
  "publicKey": "-----BEGIN PUBLIC KEY-----...",
  "name": "lobby-display-01",
  "location": "Main Building Lobby",
  "config": {
    "url": "https://example.com/display",
    "zoomFactor": 1.6,
    "fullscreen": true,
    "frame": false
  },
  "status": "online",
  "system": {
    "cpu": { ... },
    "osInfo": { ... },
    "system": { ... },
    "defaultNetworkInterface": { ... }
  },
  "timestamps": {
    "createdAt": "2026-01-01T10:00:00Z",
    "adoptedAt": "2026-01-01T10:05:00Z",
    "lastSeenAt": "2026-01-13T12:00:00Z",
    "lastConfigChangeAt": "2026-01-05T14:30:00Z"
  },
  "stats": {
    "uptime": 86400,
    "ip": "192.168.1.100",
    "currentUrl": "https://example.com/display"
  }
}
```

## Authentication

### Device Authentication

Devices authenticate using **Ed25519 signatures** (see Security Model above).

**Required headers for all device requests (except announce):**

| Header | Description |
|--------|-------------|
| `X-Device-Id` | Device UUID assigned during adoption |
| `X-Timestamp` | ISO 8601 timestamp of request |
| `X-Signature` | Base64-encoded Ed25519 signature |

The backend:
1. Looks up device by `X-Device-Id`
2. Retrieves stored public key
3. Verifies signature against request payload
4. Rejects if signature invalid or timestamp too old (>5 min)

### Admin Authentication

Standard JWT or session-based authentication for the admin panel.

## Polling vs WebSocket

**Current approach: Polling**

- Simple to implement
- Works through firewalls/NAT
- Polling interval: 30-60 seconds
- Commands may have slight delay

**Future consideration: WebSocket**

For real-time control, consider adding WebSocket support:
- Instant command delivery
- Real-time status updates
- Requires persistent connection

## Error Responses

```json
{
  "error": {
    "code": "DEVICE_NOT_FOUND",
    "message": "Device with ID xxx not found"
  }
}
```

| HTTP Status | Code | Description |
|-------------|------|-------------|
| 400 | `INVALID_REQUEST` | Malformed request |
| 401 | `UNAUTHORIZED` | Missing or invalid token |
| 403 | `FORBIDDEN` | Device not adopted |
| 404 | `DEVICE_NOT_FOUND` | Device doesn't exist |
| 409 | `ALREADY_ADOPTED` | Device already adopted |

## Implementation Priority

### Phase 1: Basic Registration
1. `POST /devices/announce` - Device registration
2. `GET /devices` - List devices (admin)
3. `POST /devices/{id}/adopt` - Adopt device

### Phase 2: Configuration
4. `GET /devices/{id}/poll` - Device polling
5. `PUT /devices/{id}` - Update config
6. `POST /devices/{id}/heartbeat` - Health monitoring

### Phase 3: Commands
7. `POST /devices/{id}/commands` - Send commands
8. `POST /devices/{id}/screenshot` - Screenshot upload

### Phase 4: Advanced
9. Batch operations
10. Device groups/sites
11. Scheduling (display on/off times)
12. WebSocket support

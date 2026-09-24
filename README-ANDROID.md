# cmkagent v1.3.1 - Hybrid Preview

Native Android monitoring agent for Checkmk Community.

- Package: `com.bcp.checkmkagent`
- App name: `cmkagent`
- Version: `1.3.0`
- Build: Java 17 + Android SDK + Gradle
- Primary transport: Checkmk PULL over TCP/6556
- Backup transport: HTTP/HTTPS PUSH to a configurable receiver
- Target production PDA: Newland MT93 (generic Android also supported)

## Hybrid behavior

`cmkagent` keeps the normal Checkmk Community pull listener running on TCP/6556. Pull remains the primary monitoring path.

When PUSH backup is enabled and a receiver URL is configured, the foreground service also sends the same Checkmk agent output periodically to the receiver. The receiver therefore keeps a warm copy of the most recent agent data.

```text
Checkmk Community ---- PULL TCP/6556 ----> Android cmkagent
                                             |
                                             +---- PUSH HTTP(S) ----> receiver cache
```

The Android app does not decide when Checkmk should use the backup. The future server-side data source program will implement:

1. try PULL first;
2. if PULL fails, read the most recent PUSH cache;
3. if both are unavailable/stale, report the host as unavailable.

## Android settings

The Settings card now includes:

- Hostname
- Pull TCP port (default 6556)
- Allowed Checkmk server IP
- Battery design capacity
- Enable PUSH backup
- Push Receiver URL
- Push Token
- Push Interval (minimum 60 seconds; default 120)
- Auto start after boot
- TEST PUSH NOW button

Recommended test configuration for the current OMV server:

```text
Allowed Checkmk Server IP : 192.168.55.112
Push Receiver URL          : http://192.168.55.112:18080/api/v1/agent
Push Interval              : 120
```

For production use HTTPS. HTTP is enabled in this preview only so the transport can be tested quickly inside the internal LAN.

## Checkmk services

The existing Android metrics remain, and v1.3.1 adds:

- `Transport_Status`

`Transport_Status` shows:

- PULL primary port
- PUSH receiver
- push interval
- last push timestamp
- last HTTP response code
- push successes/failures

## Compact UI

The accordion/dropdown UI from v1.2.0 remains. v1.3.1 adds a separate **HYBRID TRANSPORT** card.

Cards:

- AGENT
- HYBRID TRANSPORT
- BATTERY
- SYSTEM
- NETWORK
- DEVICE
- SETTINGS
- DIAGNOSTICS

## Test receiver

The ZIP includes `server-test/receiver.py`, a Python standard-library test endpoint. It is only for testing Android PUSH and does not yet integrate the cache into Checkmk.

On the OMV host:

```bash
python3 receiver.py \
  --listen 0.0.0.0 \
  --port 18080 \
  --data-dir ./push-cache \
  --token cmk-test-token
```

Then configure the APK:

```text
Push Receiver URL : http://192.168.55.112:18080/api/v1/agent
Push Token        : cmk-test-token
Push Interval     : 120
```

Tap **TEST PUSH NOW**. HTTP 200 indicates the push transport works.

## Build using GitHub Actions

Copy/replace the `android/` folder and `.github/workflows/build-cmkagent.yml` in the `configcmk` repository.

A push affecting `android/**` starts the workflow automatically.

Artifact:

```text
cmkagent-v1.3.1-debug
└── cmkagent-v1.3.1-debug.apk
```

## Security notes

This is a hybrid preview build for an internal test network.

- Pull access can be restricted to `192.168.55.112`.
- Push supports Bearer token authentication.
- The token is currently stored in Android SharedPreferences; production hardening can move it to Android Keystore.
- Prefer HTTPS in production.
- The test receiver is not a production service.


## Rekomendasi Resource dan Interval

- Pull tetap primary, mengikuti interval Checkmk (umumnya sekitar 60 detik).
- Push backup default 300 detik untuk mengurangi wake-up jaringan pada PDA yang dipakai sepanjang hari.
- Listener TCP menggunakan blocking `ServerSocket.accept()` sehingga hampir tidak memakai CPU saat idle.
- Aplikasi tidak melakukan scanning berat terus-menerus; metrik dibaca saat pull atau saat jadwal push.
- Untuk Newland MT93 4 GB RAM, verifikasi penggunaan aktual dengan Android Settings atau `adb shell dumpsys meminfo com.bcp.checkmkagent`.

## UI

Semua section memakai accordion/dropdown dan default dalam kondisi collapsed agar layar tidak terlalu panjang. Tekan section untuk membuka detail.

---
**Dibuat oleh IT OPS HQEJBNT**

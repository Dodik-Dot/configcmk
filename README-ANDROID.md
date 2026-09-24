# cmkagent v1.1.0

Custom Android pull agent for Checkmk Community.

- Package: `com.bcp.checkmkagent`
- App name: `cmkagent`
- Pull port: TCP `6556`
- Target device: Newland MT93 WMS PDA (also works on generic Android devices)
- Checkmk server in the current environment: `192.168.55.112`

## v1.1 highlights

- Redesigned dark dashboard UI for warehouse/PDA usage.
- New original CMK monitoring icon.
- Foreground listener with boot autostart.
- Optional source-IP allowlist for the Checkmk server.
- Newland MT93 profile: fallback design capacity `5000 mAh` when Android/vendor data is unavailable.
- Battery full-capacity estimate is smoothed using a rolling median of recent valid samples.
- Diagnostic counters for accepted/rejected pulls.
- No WMS application inspection in this version.

## Checkmk services

| Service | Warning | Critical |
|---|---:|---:|
| `Battery_Level` | < 30% | < 15% |
| `Health_Battery` | < 75% estimated health | < 60% |
| `Battery_Temperature` | >= 42 C | >= 48 C |
| `Battery_Voltage` | informational | informational |
| `Battery_Current` | informational | informational |
| `RAM_Usage` | >= 85% | >= 95% |
| `Storage_Usage` | >= 85% | >= 95% |
| `WiFi_Status` | <= -68 dBm | <= -75 dBm |
| `Android_Info` | informational | informational |
| `Agent_Status` | informational / diagnostics | informational |

## Collection schedule

The APK does **not** run a continuous metrics polling loop. It waits on TCP 6556 and collects metrics only when Checkmk connects.

Recommended Checkmk monitoring interval for WMS PDA devices: **60 seconds**.

This gives near-real-time battery/Wi-Fi visibility without having the Android app scan continuously in the background.

## Production settings for the WMS network

Example:

- Hostname: `PDA-10-FAUZI`
- Port: `6556`
- Design capacity: `0` (auto; MT93 falls back to 5000 mAh)
- Allowed Checkmk Server IP: `192.168.55.112`
- Start after boot: enabled

Leave `Allowed Checkmk Server IP` empty during ad-hoc testing if the test client is not the Checkmk server. For production, set it to `192.168.55.112`.

## Build APK with GitHub Actions

Open:

`Actions -> Build cmkagent APK -> Run workflow`

After the workflow succeeds, download artifact `cmkagent-debug`. Extract it to get `cmkagent-debug.apk`.

## Test

From the Checkmk host/container:

```bash
nc <PDA_IP> 6556
```

The output contains `<<<check_mk>>>` and `<<<local:sep(0)>>>` sections with the services above.

## Battery health note

`Estimated Full Capacity` and `Estimated Health` are estimates when the Android device does not expose a hardware `charge_full` value. The app explicitly reports the source of design/full capacity. On Newland MT93, the app uses a 5000 mAh device-profile fallback only if Android/vendor values are unavailable.

# cmkagent Android MVP

Package: `com.bcp.checkmkagent`  
App name: `cmkagent`  
Protocol: Checkmk Community pull  
TCP port: `6556` (configurable)

## Services exported to Checkmk

- `Health_Battery`
- `RAM_Usage`
- `Storage_Usage`

The app tries to read battery design/full capacity from Android kernel sysfs first. If unavailable, it tries Android's internal PowerProfile design capacity and then the manually configured design capacity. Current full capacity falls back to an estimate from charge counter and current battery percentage.

## First test

1. Install the debug APK on one PDA/phone.
2. Open `cmkagent`.
3. Set Hostname, for example `PDA-10-FAUZI`.
4. Keep TCP port `6556`.
5. Design Capacity can be `0` for automatic detection, or enter the factory mAh from the battery/PDA specification.
6. Tap **Simpan & Start Agent**.
7. From the Checkmk/OMV server test:

```bash
nc <IP_ANDROID> 6556
```

Expected shape:

```text
<<<check_mk>>>
Version: 1.0.0
AgentOS: android
Hostname: PDA-10-FAUZI

<<<local:sep(0)>>>
0 "Health_Battery" battery_level=86|battery_health=86.4 Status : OK | Battery Level : 86% | Design Capacity : 5000 mAh | Current Full Capacity : 4320 mAh (Est.) | Health : 86.4% | Temperature : 33.2 C | Voltage : 4.12 V | Current Status Baterai : Discharging
0 "RAM_Usage" ram_used=54 Status : OK | Used : 54% | Free : 1.84 GB | Total : 4.00 GB
0 "Storage_Usage" storage_used=62 Status : OK | Used : 62% | Free : 24.32 GB | Total : 64.00 GB
```

## GitHub Actions build

Copy the `android/` directory and `.github/workflows/build-cmkagent.yml` into the root of `Dodik-Dot/configcmk`.

Then open:

`GitHub -> Actions -> Build cmkagent APK -> Run workflow`

After the job completes, download artifact `cmkagent-debug`; inside it is `cmkagent-debug.apk`.

The debug APK is signed automatically by the Android build system and can be sideloaded for testing.

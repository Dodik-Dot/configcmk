$ErrorActionPreference = 'SilentlyContinue'

$fanSpeed   = 0$sensorName = "Dell EC"

# 1. Prioritaskan HKCU dari user yang sedang login aktif
if (Test-Path "HKCU:\Software\HWiNFO64\VSB") {
    $props = Get-ItemProperty -Path "HKCU:\Software\HWiNFO64\VSB"
    if ($props.ValueRaw15 -and [int]$props.ValueRaw15 -gt 0) {
        $fanSpeed   = [int]$props.ValueRaw15
        $sensorName = if ($props.Label15) { "HWiNFO ($($props.Label15))" } else { "Dell EC" }
    }
}

# 2. Jika dijalankan oleh SYSTEM Agent, telusuri hive semua User
if ($fanSpeed -eq 0) {
    $userHives = Get-ChildItem Registry::HKEY_USERS -ErrorAction SilentlyContinue \vert{} Where-Object {$_.Name -notmatch "_Classes$" -and $_.Name -like "S-1-5-21-*" }
    foreach ($u in $userHives) {$regPath = "Registry::$($u.Name)\Software\HWiNFO64\VSB"
        if (Test-Path $regPath) {
            $props = Get-ItemProperty -Path$regPath
            if ($props.ValueRaw15 -and [int]$props.ValueRaw15 -gt 0) {
                $fanSpeed   = [int]$props.ValueRaw15
                $sensorName = if ($props.Label15) { "HWiNFO ($($props.Label15))" } else { "Dell EC" }
                break
            }
        }
    }
}

# 3. Fallback CIM/WMI
if ($fanSpeed -eq 0) {
    Get-CimInstance -ClassName Win32_Fan -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.DesiredSpeed -and [int]$_.DesiredSpeed -gt 0) {
            $fanSpeed   = [int]$_.DesiredSpeed
            $sensorName = "Win32_Fan"
        }
    }
}

# 4. Evaluasi Kondisi Kipas & Format Output Checkmk
if ($fanSpeed -gt 0) {
    # Tentukan deskripsi kondisi berdasarkan rentang RPM
    if ($fanSpeed -ge 5500) {$kondisi = "Maximum / Turbo"
        $state   = 0   # Ubah ke 1 jika ingin Checkmk memunculkan WARN saat kipas dipaksa turbo
    } elseif ($fanSpeed -ge 4500) {$kondisi = "High Speed (Heavy Load)"
        $state   = 0
    } elseif ($fanSpeed -ge 2500) {$kondisi = "Medium (Active Cooling)"
        $state   = 0     } else {$kondisi = "Low / Silent (Normal)"
        $state   = 0
    }

    # Format: <State> <Service> <PerfData> <Summary Text>
    Write-Output "$state `"FAN_Health`" fan_speed=${fanSpeed};5500;6000;0;6500 Status: OK - FAN Speed: ${fanSpeed} rpm - Kondisi:$kondisi"
} else {
    Write-Output "0 `"FAN_Health`" fan_speed=0;5500;6000;0;6500 Status: OK - FAN Speed: 0 rpm - Kondisi: Passive (Idle/Off)"
}

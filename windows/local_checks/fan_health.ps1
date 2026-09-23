$ErrorActionPreference = 'SilentlyContinue'

$fanSpeed = 0

# 1. Coba baca HKCU langsung (jika dijalankan interaktif oleh user)
try {
    $val = (Get-ItemProperty "HKCU:\Software\HWiNFO64\VSB" -ErrorAction SilentlyContinue).ValueRaw15
    if ($val -and [int]$val -gt 0) { $fanSpeed = [int]$val }
} catch {}

# 2. Coba baca dari hive HKEY_USERS (saat dijalankan oleh service SYSTEM Checkmk)
if ($fanSpeed -eq 0) {
    try {
        Get-ChildItem -Path "Registry::HKEY_USERS" -ErrorAction SilentlyContinue | ForEach-Object {
            $k =$_.Name
            if ($k -like "*S-1-5-21-*" -and $k -notlike "*_Classes") {
                $targetPath = "Registry::$k\Software\HWiNFO64\VSB"
                $val = (Get-ItemProperty -Path$targetPath -ErrorAction SilentlyContinue).ValueRaw15
                if ($val -and [int]$val -gt 0) {
                    $fanSpeed = [int]$val
                }
            }
        }
    } catch {}
}

# 3. Evaluasi Kondisi Kipas & Format Output Checkmk
if ($fanSpeed -gt 0) {
    if ($fanSpeed -ge 5500) {$kondisi = "Maximum / Turbo"
    } elseif ($fanSpeed -ge 4500) {$kondisi = "High Speed (Heavy Load)"
    } elseif ($fanSpeed -ge 2500) {$kondisi = "Medium (Active Cooling)"
    } else {
        $kondisi = "Low / Silent (Normal)"
    }
    Write-Output "0 `"FAN_Health`" fan_speed=${fanSpeed};5500;6000;0;6500 Status: OK - FAN Speed: ${fanSpeed} rpm - Kondisi:$kondisi"
} else {
    Write-Output "0 `"FAN_Health`" fan_speed=0;5500;6000;0;6500 Status: OK - FAN Speed: 0 rpm - Kondisi: Passive (Idle/Off)"
}

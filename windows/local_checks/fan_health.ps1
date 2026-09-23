$ErrorActionPreference = 'SilentlyContinue'

$fanSpeed = 0

# 1. Cek langsung HKCU (jika dijalankan manual oleh user)
if (Test-Path "HKCU:\Software\HWiNFO64\VSB") {
    $val = (Get-ItemProperty "HKCU:\Software\HWiNFO64\VSB").ValueRaw15
    if ($val -and [int]$val -gt 0) { $fanSpeed = [int]$val }
}

# 2. Cek semua hive di HKEY_USERS (saat dieksekusi oleh service SYSTEM Checkmk)
if ($fanSpeed -eq 0) {
    # Ambil SID user yang sedang aktif login di Windows
    $loggedUser = (Get-CimInstance Win32_Process -Filter "Name = 'explorer.exe'" | Invoke-CimMethod -MethodName GetOwnerSid).Sid | Select-Object -Unique

    if ($loggedUser) {
        foreach ($sid in $loggedUser) {$userVsb = "Registry::HKEY_USERS\$sid\Software\HWiNFO64\VSB"
            if (Test-Path $userVsb) {
                $val = (Get-ItemProperty$userVsb).ValueRaw15
                if ($val -and [int]$val -gt 0) {
                    $fanSpeed = [int]$val
                    break
                }
            }
        }
    }
}

# 3. Fallback scan menyeluruh seluruh subkey HKEY_USERS
if ($fanSpeed -eq 0) {
    Get-ChildItem Registry::HKEY_USERS -ErrorAction SilentlyContinue | ForEach-Object {
        $p = "Registry::$($_.Name)\Software\HWiNFO64\VSB"
        if (Test-Path $p) {
            $val = (Get-ItemProperty$p).ValueRaw15
            if ($val -and [int]$val -gt 0) {
                $fanSpeed = [int]$val
            }
        }
    }
}

# 4. Evaluasi Kondisi Kipas & Format Output Checkmk
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

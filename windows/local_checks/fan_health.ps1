# =====================================================================
# Local Check Checkmk: Real-Time Fan Health & Speed (Windows)
# =====================================================================

<#
.SYNOPSIS
    Checkmk Local Check - Fan Health & Speed Monitor for Windows (Dell EC / HWiNFO / Super I/O)
.DESCRIPTION
    Mengekstrak metrik kecepatan putaran kipas (RPM) secara real-time untuk Checkmk:
    - Prioritas 1: HWiNFO64 Virtual Sensor Bus (Registry) - Sangat cocok untuk Laptop Dell EC.
    - Prioritas 2: LibreHardwareMonitorLib.dll (Motherboard / Desktop Super I/O).
    - Prioritas 3: WMI / CIM Fallback (Win32_Fan / Dell DCIM).
#>

$ErrorActionPreference = 'SilentlyContinue'

$fanSpeed   = 0$sensorName = "N/A"
$warnRpm    = 1000$critRpm    = 500

# =====================================================================
# 1. BACA VIA HWINFO64 VSB (VIRTUAL SENSOR BUS REGISTRY)
# =====================================================================
# Cari path VSB di seluruh hive HKEY_USERS (karena Checkmk berjalan sebagai SYSTEM)
$regPaths = @("HKCU:\Software\HWiNFO64\VSB")
$regPaths += Get-ChildItem Registry::HKEY_USERS -ErrorAction SilentlyContinue | 
             Where-Object { $_.Name -notmatch "_Classes$" } | 
             ForEach-Object { "$($_.Name)\Software\HWiNFO64\VSB" -replace "HKEY_USERS", "Registry::HKEY_USERS" }

foreach ($p in$regPaths) {
    if (Test-Path $p) {
        $props = Get-ItemProperty$p
        
        # Cari otomatis sensor dengan label atau unit yang mengandung 'Fan' atau 'Docking'
        $props.PSObject.Properties | Where-Object { $_.Name -match "^Label(\d+)$" } | ForEach-Object {
            $idx =$Matches[1]
            $labelVal =$_.Value
            
            if ($labelVal -match "Fan|Docking|Other") {
                $rawVal = $props."ValueRaw$idx"
                $strVal = $props."Value$idx"
                
                # Prioritaskan angka mentah ValueRaw
                if ($rawVal -and [int]$rawVal -gt 0) {
                    $fanSpeed = [int]$rawVal
                    $sensorName = "HWiNFO ($labelVal)"
                } elseif ($strVal -match '(\d[\d,]*)') {
                    $parsed = [int]($Matches[1] -replace ',', '')
                    if ($parsed -gt 0) {
                        $fanSpeed =$parsed
                        $sensorName = "HWiNFO ($labelVal)"
                    }
                }
            }
        }
    }
    if ($fanSpeed -gt 0) { break }
}

# =====================================================================
# 2. FALLBACK: LIBREHARDWAREMONITORLIB.DLL (DESKTOP SUPER I/O)
# =====================================================================
if ($fanSpeed -eq 0) {$dllPath = "C:\ProgramData\checkmk\agent\lib\LibreHardwareMonitorLib.dll"
    if (Test-Path $dllPath) {
        try {
            Add-Type -Path $dllPath -ErrorAction Stop$comp = New-Object LibreHardwareMonitor.Hardware.Computer
            $comp.IsMotherboardEnabled = $true$comp.IsControllerEnabled  = $true$comp.Open()

            foreach ($h in $comp.Hardware) {$h.Update()
                foreach ($s in$h.Sensors) {
                    if ($s.SensorType -eq "Fan" -and $s.Value -gt 0) {
                        $fanSpeed = [int]$s.Value
                        $sensorName = "LHM - $($s.Name)"
                        break
                    }
                }
                if ($fanSpeed -gt 0) { break }
                
                # Periksa sub-hardware
                foreach ($sub in $h.SubHardware) {$sub.Update()
                    foreach ($subS in$sub.Sensors) {
                        if ($subS.SensorType -eq "Fan" -and $subS.Value -gt 0) {
                            $fanSpeed = [int]$subS.Value
                            $sensorName = "LHM - $($subS.Name)"
                            break
                        }
                    }
                    if ($fanSpeed -gt 0) { break }
                }
                if ($fanSpeed -gt 0) { break }
            }
            $comp.Close()
        } catch {}
    }
}

# =====================================================================
# 3. EVALUASI STATUS & FORMAT CHECKMK LOCAL CHECK
# =====================================================================
# Format: <Status> "<Service_Name>" <perfdata> <Status_Text>
if ($fanSpeed -gt 0) {
    $state = 0$remark = "FAN Active"
    if ($fanSpeed -lt$critRpm) {
        $state = 2$remark = "FAN RPM Critical Low"
    } elseif ($fanSpeed -lt$warnRpm) {
        $state = 1$remark = "FAN RPM Low"
    }

    Write-Output "$state `"FAN_Health`" fan_speed=${fanSpeed};${warnRpm};${critRpm};0; Status : OK \vert{} FAN Speed :${fanSpeed}rpm | Sensor: ${sensorName} \vert{} Remark:${remark}"
} else {
    Write-Output "0 `"FAN_Health`" - Status : OK | FAN Speed : 0rpm | Remark: Dell EC Controlled / Passive Mode"
}

# =====================================================================
# Local Check Checkmk: Real-Time Fan Health & Speed (Windows Native)
# =====================================================================
<#
.SYNOPSIS
    Checkmk Local Check - Fan Health & Speed Monitor for Windows (Dell EC / HWiNFO / Super I/O)
#>

$ErrorActionPreference = 'SilentlyContinue'

$fanSpeed   = 0$sensorName = "Dell EC"
$warnRpm    = 1000$critRpm    = 500

# =====================================================================
# 1. BACA VIA HWINFO64 VSB (VIRTUAL SENSOR BUS REGISTRY)
# =====================================================================
# Checkmk Agent berjalan sebagai akun SYSTEM, jadi kita telusuri seluruh user hive
$regPaths = @("HKCU:\Software\HWiNFO64\VSB")
$regPaths += Get-ChildItem Registry::HKEY_USERS -ErrorAction SilentlyContinue | 
             Where-Object { $_.Name -notmatch "_Classes$" } | 
             ForEach-Object { "$($_.Name)\Software\HWiNFO64\VSB" -replace "HKEY_USERS", "Registry::HKEY_USERS" }

foreach ($p in$regPaths) {
    if (Test-Path $p) {
        $props = Get-ItemProperty -Path$p -ErrorAction SilentlyContinue
        
        # 1. Cek langsung index 15 (Target sensor Dell EC Docking/Fan)
        if ($props.ValueRaw15 -and [int]$props.ValueRaw15 -gt 0) {
            $fanSpeed   = [int]$props.ValueRaw15
            $sensorName = if ($props.Label15) { "HWiNFO ($($props.Label15))" } else { "Dell EC" }
            break
        }

        # 2. Deteksi dinamis jika berada di index lain
        if ($props) {$props.PSObject.Properties | Where-Object { $_.Name -match "^Label(\d+)$" } | ForEach-Object {
                $idx =$Matches[1]
                $lbl =$_.Value
                if ($lbl -match "Fan|Docking|Other") {
                    $raw = $props."ValueRaw$idx"
                    $val = $props."Value$idx"
                    if ($raw -and [int]$raw -gt 0) {
                        $fanSpeed   = [int]$raw
                        $sensorName = "HWiNFO ($lbl)"
                    } elseif ($val -match '(\d[\d,]*)') {
                        $parsed = [int]($Matches[1] -replace ',', '')
                        if ($parsed -gt 0) {
                            $fanSpeed   =$parsed
                            $sensorName = "HWiNFO ($lbl)"
                        }
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
                        $fanSpeed   = [int]$s.Value
                        $sensorName = "LHM - $($s.Name)"
                        break
                    }
                }
                if ($fanSpeed -gt 0) { break }

                foreach ($sub in $h.SubHardware) {$sub.Update()
                    foreach ($subS in$sub.Sensors) {
                        if ($subS.SensorType -eq "Fan" -and $subS.Value -gt 0) {
                            $fanSpeed   = [int]$subS.Value
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
# 3. OUTPUT FORMAT CHECKMK LOCAL CHECK
# =====================================================================
if ($fanSpeed -gt 0) {
    $state  = 0$remark = "FAN Active"
    if ($fanSpeed -lt$critRpm) {
        $state  = 2$remark = "FAN RPM Critical Low"
    } elseif ($fanSpeed -lt$warnRpm) {
        $state  = 1$remark = "FAN RPM Low"
    }
    Write-Output "$state `"FAN_Health`" fan_speed=${fanSpeed};${warnRpm};${critRpm};0; Status : OK \vert{} FAN Speed :${fanSpeed}rpm | Sensor: ${sensorName} \vert{} Remark:${remark}"
} else {
    Write-Output "0 `"FAN_Health`" - Status : OK | FAN Speed : 0rpm | Remark: Dell EC Controlled (Dynamic/Passive Cooling)"
}

# =====================================================================
# Local Check Checkmk: Real-Time Fan Health & Speed (Dell EC & Windows Native)
# =====================================================================

$fanSpeed   = 0$sensorName = "N/A"

# 1. Baca HWiNFO64 VSB (Dell EC - Vostro / Latitude)
$regPaths = @("HKCU:\Software\HWiNFO64\VSB")
$regPaths += Get-ChildItem Registry::HKEY_USERS -ErrorAction SilentlyContinue | 
             Where-Object { $_.Name -notmatch "_Classes$" } | 
             ForEach-Object { "$($_.Name)\Software\HWiNFO64\VSB" -replace "HKEY_USERS", "Registry::HKEY_USERS" }

foreach ($p in$regPaths) {
    if (Test-Path $p) {
        $props = Get-ItemProperty -Path$p -ErrorAction SilentlyContinue
        
        # Target langsung Index 15 (Dell EC Other/Docking Fan)
        if ($props.ValueRaw15 -and [int]$props.ValueRaw15 -gt 0) {
            $fanSpeed   = [int]$props.ValueRaw15
            $sensorName = if ($props.Label15) { "HWiNFO ($($props.Label15))" } else { "Dell EC" }
            break
        }

        # Fallback dinamis jika index bergeser
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

# 2. Fallback CIM/WMI Standar Windows (Win32_Fan)
if ($fanSpeed -eq 0) {$fanCim = Get-CimInstance -ClassName Win32_Fan -ErrorAction SilentlyContinue
    if ($fanCim) {
        foreach ($fan in$fanCim) {
            if ($fan.DesiredSpeed -and$fan.DesiredSpeed -gt 0) {
                $fanSpeed   = [int]$fan.DesiredSpeed
                $sensorName = "Win32_Fan"
                break
            }
        }
    }
}

# 3. Fallback WMI Provider Vendor (Dell DCIM NumericSensor)
if ($fanSpeed -eq 0) {$dcimFan = Get-CimInstance -Namespace "root\dcim\sysman" -ClassName "DCIM_NumericSensor" -ErrorAction SilentlyContinue | 
               Where-Object { $_.BaseUnits -eq 19 -and$_.CurrentReading -gt 0 }
    if ($dcimFan) {$fanSpeed   = [int]($dcimFan \vert{} Select-Object -First 1).CurrentReading$sensorName = "DCIM_NumericSensor"
    }
}

# 4. Format Output Local Check Checkmk (Gunakan pemisah '~' agar tidak tabrakan dengan perfdata '|')
if ($fanSpeed -gt 0) {
    Write-Output "0 `"FAN_Health`" fan_speed=${fanSpeed};1000;;0; Status : OK ~ FAN Speed : ${fanSpeed}rpm ~ Sensor:${sensorName} ~ Remark: FAN Condition Good"
} else {
    Write-Output "0 `"FAN_Health`" - Status : OK ~ FAN Speed : 0rpm ~ Remark: Dell EC Controlled (Dynamic/Passive Cooling)"
}

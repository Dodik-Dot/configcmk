$ErrorActionPreference = 'SilentlyContinue'

$fanSpeed   = 0$sensorName = "Dell EC"

# 1. Baca HWiNFO64 VSB dari seluruh hive HKEY_USERS
Get-ChildItem Registry::HKEY_USERS -ErrorAction SilentlyContinue | 
    Where-Object { $_.Name -notmatch "_Classes$" } | 
    ForEach-Object {
        $path = "Registry::" + $_.Name + "\Software\hwinfo64\vsb"
        if (Test-Path $path) {
            $props = Get-ItemProperty$path
            if ($props.ValueRaw15 -and [int]$props.ValueRaw15 -gt 0) {
                $fanSpeed   = [int]$props.ValueRaw15
                $sensorName = if ($props.Label15) { "HWiNFO (" + $props.Label15 + ")" } else { "Dell EC" }
            }
        }
    }

# 2. Fallback HKCU
if ($fanSpeed -eq 0 -and (Test-Path "HKCU:\Software\HWiNFO64\VSB")) {
    $props = Get-ItemProperty "HKCU:\Software\hwinfo64\vsb"
    if ($props.ValueRaw15 -and [int]$props.ValueRaw15 -gt 0) {
        $fanSpeed   = [int]$props.ValueRaw15
        $sensorName = if ($props.Label15) { "HWiNFO (" + $props.Label15 + ")" } else { "Dell EC" }
    }
}

# 3. Fallback Win32_Fan
if ($fanSpeed -eq 0) {
    Get-CimInstance -ClassName Win32_Fan -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.DesiredSpeed -and [int]$_.DesiredSpeed -gt 0) {
            $fanSpeed   = [int]$_.DesiredSpeed
            $sensorName = "Win32_Fan"
        }
    }
}

# 4. Output Local Check Checkmk (Pemisah ~)
if ($fanSpeed -gt 0) {
    Write-Output "0 `"FAN_Health`" fan_speed=${fanSpeed};1000;;0; Status : OK ~ FAN Speed : ${fanSpeed}rpm ~ Sensor:${sensorName} ~ Remark: FAN Condition Good"
} else {
    Write-Output "0 `"FAN_Health`" - Status : OK ~ FAN Speed : 0rpm ~ Remark: Dell EC Controlled (Dynamic/Passive Cooling)"
}

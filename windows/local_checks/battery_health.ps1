# =====================================================================
# Local Check Checkmk: Daily Battery Health Monitor (Windows)
# Scheduled to run once a day at 16:00
# =====================================================================
$CacheDir = "$env:ProgramData\checkmk\agent\cache"
if (-not (Test-Path $CacheDir)) { New-Item -ItemType Directory -Force $CacheDir | Out-Null }
$CacheFile = Join-Path $CacheDir "cache_battery_health.txt"

# Get current hour and today's 16:00 threshold
$Now = Get-Date
$Today16 = Get-Date -Hour 16 -Minute 0 -Second 0
if ($Now -lt $Today16) {
    $Last16 = $Today16.AddDays(-1)
} else {
    $Last16 = $Today16
}

$NeedUpdate = $true
if (Test-Path $CacheFile) {
    $CacheMtime = (Get-Item $CacheFile).LastWriteTime
    if ($CacheMtime -ge $Last16) {
        $NeedUpdate = $false
    }
}

if ($NeedUpdate) {
    # Query battery using CIM
    $Battery = Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue
    
    if ($Battery) {
        $DesignCapacity = $Battery.DesignCapacity # mWh
        $FullChargeCapacity = $Battery.FullChargeCapacity # mWh
        $BatteryLevel = $Battery.EstimatedChargeRemaining # %
        
        # State: 1 = Discharging, 2 = AC Power (Charging/Fully Charged)
        $StateVal = $Battery.BatteryStatus
        $State = "Unknown"
        if ($StateVal -eq 1) { $State = "Discharging" }
        elseif ($StateVal -eq 2) { $State = "Fully Charged" }
        elseif ($StateVal -eq 6) { $State = "Charging" }
        else { $State = "AC Power" }
        
        # Health SOH
        if ($DesignCapacity -and $FullChargeCapacity -and $DesignCapacity -gt 0) {
            $Health = [int](($FullChargeCapacity / $DesignCapacity) * 100)
            if ($Health -gt 100) { $Health = 100 }
        } else {
            $Health = 100
        }
        
        $DesignWh = [int]($DesignCapacity / 1000)
        $FullWh = [int]($FullChargeCapacity / 1000)
        if ($DesignWh -eq 0) { $DesignWh = 35 }
        if ($FullWh -eq 0) { $FullWh = 10 }
        
        # Thresholds: OK >= 60%, WARNING <= 40%, CRITICAL <= 20%
        $Status = 0
        $StatusTxt = "OK"
        if ($Health -le 20) {
            $Status = 2
            $StatusTxt = "Critical"
        } elseif ($Health -le 40) {
            $Status = 1
            $StatusTxt = "Warning"
        }
        
        $Output = "$Status `"Health_Battery`" -  Status Battery : $State | Design Capacity : $($DesignWh)w/h | Current Capacity : $($FullWh)w/h | Health : $($Health)% | Battery Level : $($BatteryLevel)%"
    } else {
        # PC Desktop / No Battery
        $Output = "0 `"Health_Battery`" -  Status Battery : N/A | Device is PC/Desktop, there is no battery."
    }
    
    $Output | Out-File -FilePath $CacheFile -Encoding utf8 -Force
}

Get-Content $CacheFile -ErrorAction SilentlyContinue

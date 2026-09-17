# =====================================================================
# Local Check Checkmk: Daily Storage Health Monitor (Windows)
# Scheduled to run once a day at 16:00
# =====================================================================
$CacheDir = "$env:ProgramData\checkmk\agent\cache"
if (-not (Test-Path $CacheDir)) { New-Item -ItemType Directory -Force $CacheDir | Out-Null }
$CacheFile = Join-Path $CacheDir "cache_disk_health.txt"

# Logika Penjadwalan Cache Harian Pukul 16:00
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
    if (Test-Path $CacheFile) { Remove-Item $CacheFile -Force }
    
    # Ambil Physical Disks via CIM
    $Disks = Get-PhysicalDisk -ErrorAction SilentlyContinue
    
    if (-not $Disks) {
        "0 `"Storage_NVMe_Status`" - No physical disks detected on this system." | Out-File -FilePath $CacheFile -Encoding utf8 -Force
    } else {
        foreach ($Disk in $Disks) {
            $DeviceID = $Disk.DeviceID
            $Model = $Disk.FriendlyName.Trim()
            $SizeGB = [Math]::Round($Disk.Size / 1GB, 2)
            $RawMediaType = $Disk.MediaType
            $Spindle = $Disk.SpindleSpeed
            
            # =================================================================
            # 1. Klasifikasi Tipe Drive Berlapis (Fix HDD Terbaca SSD Sata)
            # =================================================================
            $IsNVMe = $false
            $IsHDD  = $false
            $IsSSD  = $false

            if ($Disk.BusType -eq "NVMe" -or $Model -match "NVMe") {
                $IsNVMe = $true
            } else {
                # A. Cek RPM Piringan (SpindleSpeed > 0 menandakan HDD)
                if ($Spindle -and $Spindle -gt 0 -and $Spindle -lt 25000) {
                    $IsHDD = $true
                }
                # B. Cek String Model Khas HDD Mekanik
                elseif ($Model -match 'WDC|WD\d{2,4}|ST\d{2,4}|BARRACUDA|TOSHIBA\s*DT|HITACHI|HGST|DESKSTAR' -and $Model -notmatch 'SSD') {
                    $IsHDD = $true
                }
                # C. Cek MediaType bawaan
                elseif ($RawMediaType -eq "HDD") {
                    $IsHDD = $true
                }
                # D. Cek jika eksplisit SSD
                elseif ($RawMediaType -eq "SSD" -or $Model -match 'SSD|Solid State') {
                    $IsSSD = $true
                }
                # E. Fallback jika masih Unspecified
                else {
                    $IsHDD = $true
                }
            }

            $DiskType = if ($IsNVMe) { "NVME" } elseif ($IsHDD) { "HDD" } else { "SSD Sata" }

            # =================================================================
            # 2. Query Storage Reliability Counter
            # =================================================================
            $Reliability = $Disk | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
            
            $Temp = 35 # Default Fallback Temp
            if ($Reliability -and $Reliability.Temperature -ne $null -and $Reliability.Temperature -gt 0) {
                $Temp = $Reliability.Temperature
            }
            
            $Poh = 0
            if ($Reliability -and $Reliability.LoadOnHours -ne $null) {
                $Poh = $Reliability.LoadOnHours
            }
            
            # Operational Status / Health
            $StatusStr = $Disk.HealthStatus # Healthy, Warning, Unhealthy
            $SmartStatus = "PASSED"
            if ($StatusStr -eq "Unhealthy") { $SmartStatus = "FAILED" }
            
            # Wearout / Health %
            $Wear = 0
            if ($Reliability -and $Reliability.Wear -ne $null) {
                $Wear = $Reliability.Wear
            }
            $Health = 100 - $Wear
            if ($Health -lt 0) { $Health = 0 }
            
            # Reads & Writes estimation in TB (Hanya untuk SSD/NVMe)
            $ReadTB = 0.0
            $WriteTB = 0.0
            if ($Reliability) {
                if ($Reliability.ReadBytesTotal) { $ReadTB = [Math]::Round($Reliability.ReadBytesTotal / 1TB, 2) }
                if ($Reliability.WriteBytesTotal) { $WriteTB = [Math]::Round($Reliability.WriteBytesTotal / 1TB, 2) }
            }
            
            # Hitung Write/Day untuk Media Flash
            $WriteDay = "N/A"
            if ($DiskType -ne "HDD" -and $Poh -gt 0 -and $WriteTB -gt 0) {
                $Days = $Poh / 24
                if ($Days -gt 0.05) {
                    $WriteDayVal = ($WriteTB * 1000) / $Days
                    $WriteDay = "$([Math]::Round($WriteDayVal, 2)) GB"
                } else {
                    $WriteDay = "0.00 GB"
                }
            }
            
            # =================================================================
            # 3. Penentuan Status Checkmk
            # =================================================================
            $StatusVal = 0
            $StatusText = "OK"
            if ($SmartStatus -eq "FAILED" -or ($DiskType -ne "HDD" -and $Health -le 80)) {
                $StatusVal = 2
                $StatusText = "Critical"
            } elseif ($DiskType -ne "HDD" -and $Health -le 90) {
                $StatusVal = 1
                $StatusText = "Warning"
            }
            
            # Bersihkan nama model untuk identifier service Checkmk
            $CleanModel = $Model -replace '[^\w\s-]', ''
            $ServiceName = "Storage_Health_$CleanModel"
            
            # =================================================================
            # 4. Format Baris Output Checkmk
            # =================================================================
            if ($DiskType -eq "HDD") {
                # Format khusus HDD Mekanik
                $OutputLine = "$StatusVal `"$ServiceName`" - Status : $StatusText | Model: $Model ($($SizeGB) GB) | Status: $SmartStatus | Temp: $($Temp)C | Disk Type: HDD | Reallocated Sectors: 0 | Pending Sectors: 0 | Power On Hours: $Poh Hrs | Remark: Disk Condition Good"
            } else {
                # Format khusus SSD / NVMe
                $ReadStr = "$($ReadTB) TB"
                $WriteStr = "$($WriteTB) TB"
                $OutputLine = "$StatusVal `"$ServiceName`" - Status : $StatusText | Model: $Model ($($SizeGB) GB) | Status: $SmartStatus | Temp: $($Temp)C | Type: $DiskType ($($SizeGB) GB) | Health: $($Health)% | Read: $ReadStr | Written: $WriteStr | Write/Day: $WriteDay"
            }
            
            $OutputLine | Out-File -FilePath $CacheFile -Encoding utf8 -Append
        }
    }
}

Get-Content $CacheFile -ErrorAction SilentlyContinue

# =====================================================================
# Local Check Checkmk: Resilient Hybrid Storage Health Monitor (Windows)
# Architecture: WMI Core Baseline + smartctl.exe Deep Diagnostic Overlay
# Scheduled to run once a day at 16:00
# =====================================================================
$ErrorActionPreference = 'SilentlyContinue'
$CacheDir  = "$env:ProgramData\checkmk\agent\cache"
if (-not (Test-Path $CacheDir)) { New-Item -ItemType Directory -Force $CacheDir | Out-Null }
$CacheFile = Join-Path $CacheDir "cache_disk_health.txt"

# 1. Logika Penjadwalan Cache Harian Pukul 16:00
$Now = Get-Date
$Today16 = Get-Date -Hour 16 -Minute 0 -Second 0
$Last16  = if ($Now -lt $Today16) { $Today16.AddDays(-1) } else { $Today16 }

$NeedUpdate = $true
if (Test-Path $CacheFile) {
    $CacheMtime = (Get-Item $CacheFile).LastWriteTime
    if ($CacheMtime -ge $Last16) {
        $NeedUpdate = $false
    }
}

if ($NeedUpdate) {
    if (Test-Path $CacheFile) { Remove-Item $CacheFile -Force }

    # Cari binary smartctl.exe
    $SmartctlBin = "C:\Program Files\smartmontools\bin\smartctl.exe"
    if (-not (Test-Path $SmartctlBin)) {
        $CmdCheck = Get-Command smartctl.exe -ErrorAction SilentlyContinue
        if ($CmdCheck) { $SmartctlBin = $CmdCheck.Source } else { $SmartctlBin = $null }
    }

    $Disks = Get-PhysicalDisk -ErrorAction SilentlyContinue
    if (-not $Disks) {
        "0 `"Storage_NVMe_Status`" - No physical disks detected." | Out-File -FilePath $CacheFile -Encoding utf8 -Force
    } else {
        foreach ($Disk in $Disks) {
            $DeviceID     = $Disk.DeviceID
            $Model        = $Disk.FriendlyName.Trim()
            $SizeGB       = [Math]::Round($Disk.Size / 1GB, 2)
            $RawMediaType = $Disk.MediaType
            $Spindle      = $Disk.SpindleSpeed

            # Klasifikasi Tipe Drive
            $IsNVMe = ($Disk.BusType -eq "NVMe" -or $Model -match "NVMe|CS2241|SX8200|MAP")
            $IsHDD  = ($Spindle -and $Spindle -gt 0 -and $Spindle -lt 25000) -or 
                      ($Model -match 'WDC|WD\d{2,4}|ST\d{2,4}|BARRACUDA|TOSHIBA\s*DT|HITACHI|HGST' -and $Model -notmatch 'SSD') -or 
                      ($RawMediaType -eq "HDD")
            $DiskType = if ($IsNVMe) { "NVME" } elseif ($IsHDD) { "HDD" } else { "SSD Sata" }

            # =========================================================
            # LANGKAH 1: Ambil Nilai Baseline dari WMI Windows
            # =========================================================
            $Health      = 100
            $Temp        = 35
            $Poh         = 0
            $SmartStatus = "PASSED"
            $ReadTB      = 0.0
            $WriteTB     = 0.0
            $Reallocated = 0
            $Pending     = 0

            # Normalisasi status kesehatan bawaan Windows (Cegah nilai '0')
            $HealthEnum = [string]$Disk.HealthStatus
            if ($HealthEnum -match "Unhealthy|2") {
                $SmartStatus = "FAILED"
            } elseif ($HealthEnum -match "Warning|1") {
                $SmartStatus = "WARNING"
            } else {
                $SmartStatus = "PASSED"
            }

            # Ekstrak data reliabilitas WMI
            $Reliability = $Disk | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
            if ($Reliability) {
                if ($Reliability.Temperature -and $Reliability.Temperature -gt 0) {
                    $Temp = [int]$Reliability.Temperature
                }
                if ($Reliability.LoadOnHours -and $Reliability.LoadOnHours -gt 0) {
                    $Poh = [int]$Reliability.LoadOnHours
                }
                if ($Reliability.Wear -ne $null) {
                    $Health = [Math]::Max(0, (100 - [int]$Reliability.Wear))
                }
                if ($Reliability.ReadBytesTotal -and $Reliability.ReadBytesTotal -gt 0) {
                    $ReadTB = [Math]::Round(([double]$Reliability.ReadBytesTotal / 1TB), 2)
                }
                if ($Reliability.WriteBytesTotal -and $Reliability.WriteBytesTotal -gt 0) {
                    $WriteTB = [Math]::Round(([double]$Reliability.WriteBytesTotal / 1TB), 2)
                }
            }

            # =========================================================
            # LANGKAH 2: Perkaya / Tambal Data Menggunakan smartctl.exe
            # =========================================================
            if ($SmartctlBin -and (Test-Path $SmartctlBin)) {
                $DevPath = "/dev/pd$DeviceID"
                
                # Coba pembacaan autodetect, jika NVMe fallback ke flag spesifik
                $SmartRaw = & $SmartctlBin -a $DevPath 2>$null
                if ($IsNVMe -and (-not ($SmartRaw -match "Data Units Written|Percentage Used"))) {
                    $SmartRaw = & $SmartctlBin -a $DevPath -d nvme 2>$null
                }

                # Tangkap status kesehatan dari smartctl jika tersedia
                if ($SmartRaw -match "SMART overall-health self-assessment test result:\s*([a-zA-Z]+)") {
                    $SmartStatus = $Matches[1].Trim()
                }

                if ($IsHDD) {
                    # Parsing atribut fisik HDD Mekanik
                    foreach ($line in $SmartRaw) {
                        if ($line -match "^\s*5\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+(\d+)") { $Reallocated = [int]$Matches[1] }
                        if ($line -match "^\s*9\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+(\d+)") { $Poh = [int]$Matches[1] }
                        if ($line -match "^\s*(190|194)\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+(\d+)") { $Temp = [int]$Matches[2] }
                        if ($line -match "^\s*197\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+(\d+)") { $Pending = [int]$Matches[1] }
                    }
                } else {
                    # NVMe & SATA SSD: Hanya timpa jika smartctl memberikan nilai riil
                    if ($SmartRaw -match "Percentage Used:\s+(\d+)") {
                        $Health = [Math]::Max(0, (100 - [int]$Matches[1]))
                    }
                    if ($SmartRaw -match "Temperature:\s+(\d+)\s+Celsius") {
                        $Temp = [int]$Matches[1]
                    }
                    if ($SmartRaw -match "Power On Hours:\s+([\d,]+)") {
                        $Poh = [int]($Matches[1] -replace ',', '')
                    }
                    if ($SmartRaw -match "Data Units Written:\s+[\d,]+\s+\[([\d.]+)\s+TB\]") {
                        $WriteTB = [double]$Matches[1]
                    } elseif ($SmartRaw -match "Data Units Written:\s+([\d,]+)") {
                        $rawW = [double]($Matches[1] -replace ',', '')
                        if ($rawW -gt 0) { $WriteTB = [Math]::Round(($rawW * 512000) / 1TB, 2) }
                    }
                    if ($SmartRaw -match "Data Units Read:\s+[\d,]+\s+\[([\d.]+)\s+TB\]") {
                        $ReadTB = [double]$Matches[1]
                    } elseif ($SmartRaw -match "Data Units Read:\s+([\d,]+)") {
                        $rawR = [double]($Matches[1] -replace ',', '')
                        if ($rawR -gt 0) { $ReadTB = [Math]::Round(($rawR * 512000) / 1TB, 2) }
                    }
                }
            }

            # =========================================================
            # LANGKAH 3: Kalkulasi Metrik & Status Checkmk
            # =========================================================
            $WriteDay = "N/A"
            if ($DiskType -ne "HDD" -and $Poh -gt 0 -and $WriteTB -gt 0) {
                $Days = $Poh / 24.0
                if ($Days -gt 0.05) {
                    $WriteDayVal = ($WriteTB * 1000.0) / $Days
                    $WriteDay = "$([Math]::Round($WriteDayVal, 2)) GB/Day"
                } else {
                    $WriteDay = "0.00 GB/Day"
                }
            }

            # Evaluasi Threshold Status Checkmk
            $StatusVal  = 0
            $StatusText = "OK"

            if ($SmartStatus -eq "FAILED" -or ($DiskType -ne "HDD" -and $Health -le 70) -or ($IsHDD -and ($Reallocated -gt 50 -or $Pending -gt 10))) {
                $StatusVal  = 2
                $StatusText = "CRITICAL"
            } elseif ($SmartStatus -eq "WARNING" -or ($DiskType -ne "HDD" -and $Health -le 85) -or ($IsHDD -and ($Reallocated -gt 0 -or $Pending -gt 0))) {
                $StatusVal  = 1
                $StatusText = "WARNING"
            }

            $CleanModel  = $Model -replace '[^\w\s-]', ''
            $ServiceName = "Storage_Health_$CleanModel"

            # Susun baris keluaran Checkmk
            if ($DiskType -eq "HDD") {
                $Remark = if ($Reallocated -eq 0 -and $Pending -eq 0) { "Kondisi Sehat (0 Bad Sector)" } else { "Waspada: $Reallocated Bad Sector / $Pending Pending" }
                $OutputLine = "$StatusVal `"$ServiceName`" - Status : $StatusText | Model: $Model ($($SizeGB) GB) | Status: $SmartStatus | Temp: $($Temp)C | Disk Type: HDD | Reallocated Sectors: $Reallocated | Pending Sectors: $Pending | Power On Hours: $Poh Jam | Remark: $Remark"
            } else {
                $OutputLine = "$StatusVal `"$ServiceName`" - Status : $StatusText | Model: $Model ($($SizeGB) GB) | Status: $SmartStatus | Temp: $($Temp)C | Type: $DiskType ($($SizeGB) GB) | Health: $($Health)% | Read: $ReadTB TB | Written: $WriteTB TB | Write/Day: $WriteDay"
            }

            $OutputLine | Out-File -FilePath $CacheFile -Encoding utf8 -Append
        }
    }
}

# Tampilkan isi cache
Get-Content $CacheFile -ErrorAction SilentlyContinue

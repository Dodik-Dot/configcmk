# =====================================================================
# Local Check Checkmk: Daily Hybrid Storage Health Monitor (Windows)
# Engine: smartctl.exe (Direct Hardware) with WMI Fallback
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
    
    # Deteksi lokasi binary smartctl.exe
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
            
            # Klasifikasi Tipe Drive Dasar
            $IsNVMe = ($Disk.BusType -eq "NVMe" -or $Model -match "NVMe")
            $IsHDD  = ($Spindle -and $Spindle -gt 0 -and $Spindle -lt 25000) -or 
                      ($Model -match 'WDC|WD\d{2,4}|ST\d{2,4}|BARRACUDA|TOSHIBA\s*DT|HITACHI|HGST' -and $Model -notmatch 'SSD') -or 
                      ($RawMediaType -eq "HDD")
            $DiskType = if ($IsNVMe) { "NVME" } elseif ($IsHDD) { "HDD" } else { "SSD Sata" }

            # Inisialisasi Nilai Metrik
            $Health      = 100
            $Temp        = 35
            $Poh         = 0
            $SmartStatus = "PASSED"
            $ReadTB      = 0.0
            $WriteTB     = 0.0
            $Reallocated = 0
            $Pending     = 0
            $ParsedViaSmartctl = $false

            # =========================================================
            # METODE A: Eksekusi smartctl.exe Langsung ke Register Drive
            # =========================================================
            if ($SmartctlBin -and (Test-Path $SmartctlBin)) {
                $DevPath = "/dev/pd$DeviceID"
                $SmartRaw = & $SmartctlBin -a $DevPath 2>$null
                
                if ($SmartRaw -and $SmartRaw.Count -gt 5) {
                    $ParsedViaSmartctl = $true
                    
                    # Cek Status SMART Overall
                    if ($SmartRaw -match "SMART overall-health self-assessment test result:\s*(\w+)") {
                        $SmartStatus = $Matches[1].Trim()
                    }

                    if ($IsNVMe) {
                        # 1. Health % dari NVMe 'Percentage Used' (Contoh: Used 5% -> Health 95%)
                        if ($SmartRaw -match "Percentage Used:\s+(\d+)") {
                            $Used = [int]$Matches[1]
                            $Health = [Math]::Max(0, (100 - $Used))
                        }

                        # 2. Suhu NVMe
                        if ($SmartRaw -match "Temperature:\s+(\d+)\s+Celsius") {
                            $Temp = [int]$Matches[1]
                        }

                        # 3. Power On Hours
                        if ($SmartRaw -match "Power On Hours:\s+([\d,]+)") {
                            $Poh = [int]($Matches[1] -replace ',', '')
                        }

                        # 4. Data Units Written (TBW) & Read
                        if ($SmartRaw -match "Data Units Written:\s+[\d,]+\s+\[([\d.]+)\s+TB\]") {
                            $WriteTB = [double]$Matches[1]
                        } elseif ($SmartRaw -match "Data Units Written:\s+([\d,]+)") {
                            $rawW = [double]($Matches[1] -replace ',', '')
                            $WriteTB = [Math]::Round(($rawW * 512000) / 1TB, 2)
                        }

                        if ($SmartRaw -match "Data Units Read:\s+[\d,]+\s+\[([\d.]+)\s+TB\]") {
                            $ReadTB = [double]$Matches[1]
                        } elseif ($SmartRaw -match "Data Units Read:\s+([\d,]+)") {
                            $rawR = [double]($Matches[1] -replace ',', '')
                            $ReadTB = [Math]::Round(($rawR * 512000) / 1TB, 2)
                        }
                    } else {
                        # Parsing Atribut SATA (SSD & HDD)
                        foreach ($line in $SmartRaw) {
                            # ID 5: Reallocated Sectors
                            if ($line -match "^\s*5\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+(\d+)") {
                                $Reallocated = [int]$Matches[1]
                            }
                            # ID 9: Power On Hours
                            if ($line -match "^\s*9\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+(\d+)") {
                                $Poh = [int]$Matches[1]
                            }
                            # ID 194/190: Temperature
                            if ($line -match "^\s*(190|194)\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+(\d+)") {
                                $Temp = [int]$Matches[2]
                            }
                            # ID 197: Current Pending Sectors
                            if ($line -match "^\s*197\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+(\d+)") {
                                $Pending = [int]$Matches[1]
                            }
                            # ID 231/202/169: SSD Health %
                            if ($line -match "^\s*(231|202|169)\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+(\d+)") {
                                $Health = [int]$Matches[2]
                            }
                            # ID 241: Lifetime Writes (SATA SSD)
                            if ($line -match "^\s*241\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+(\d+)") {
                                $rawLba = [double]$Matches[1]
                                $WriteTB = [Math]::Round(($rawLba * 512) / 1TB, 2)
                            }
                        }
                    }
                }
            }

            # =========================================================
            # METODE B: Fallback WMI jika smartctl Tidak Tersedia
            # =========================================================
            if (-not $ParsedViaSmartctl) {
                $Reliability = $Disk | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
                if ($Reliability) {
                    if ($Reliability.Temperature -and $Reliability.Temperature -gt 0) { $Temp = $Reliability.Temperature }
                    if ($Reliability.LoadOnHours) { $Poh = $Reliability.LoadOnHours }
                    if ($Reliability.Wear -ne $null) { $Health = [Math]::Max(0, (100 - $Reliability.Wear)) }
                    if ($Reliability.ReadBytesTotal)  { $ReadTB  = [Math]::Round($Reliability.ReadBytesTotal / 1TB, 2) }
                    if ($Reliability.WriteBytesTotal) { $WriteTB = [Math]::Round($Reliability.WriteBytesTotal / 1TB, 2) }
                }
                if ($Disk.HealthStatus -eq "Unhealthy") { $SmartStatus = "FAILED" }
            }

            # 2. Hitung Laju Tulis Harian (Write/Day)
            $WriteDay = "N/A"
            if ($DiskType -ne "HDD" -and $Poh -gt 0 -and $WriteTB -gt 0) {
                $Days = $Poh / 24.0
                if ($Days -gt 0.05) {
                    $WriteDayVal = ($WriteTB * 1000.0) / $Days
                    $WriteDay = "$([Math]::Round($WriteDayVal, 2)) GB"
                } else {
                    $WriteDay = "0.00 GB"
                }
            }

            # 3. Evaluasi Status Checkmk (OK / WARN / CRIT)
            $StatusVal  = 0
            $StatusText = "OK"
            if ($SmartStatus -ne "PASSED" -or ($DiskType -ne "HDD" -and $Health -le 70) -or ($IsHDD -and ($Reallocated -gt 50 -or $Pending -gt 10))) {
                $StatusVal  = 2
                $StatusText = "CRITICAL"
            } elseif (($DiskType -ne "HDD" -and $Health -le 85) -or ($IsHDD -and ($Reallocated -gt 0 -or $Pending -gt 0))) {
                $StatusVal  = 1
                $StatusText = "WARNING"
            }

            $CleanModel  = $Model -replace '[^\w\s-]', ''
            $ServiceName = "Storage_Health_$CleanModel"

            # 4. Susun Baris Output Checkmk
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

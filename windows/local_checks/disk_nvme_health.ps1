# ==========================================================
# disk_nvme_health.ps1 - Checkmk Local Check (Windows)
# Repositori: Dodik-Dot/configcmk
# Urutan sumber data (3-Tier Fallback):
#   1. smartctl            (--scan & /dev/pd* - NVMe dan SATA)
#   2. CrystalDiskInfo     (log_custom\diskinfo.txt dari Scheduled Task)
#   3. Windows Storage API (Get-PhysicalDisk + Get-StorageReliabilityCounter)
# ==========================================================
$ErrorActionPreference = 'SilentlyContinue'

# ---------- Pengaturan ----------
$WarnTemp       = 60    # derajat C
$CritTemp       = 70$WarnUsed       = 15    # % keausan (Warning jika sisa kesehatan <= 85%)
$CritUsed       = 30    # % keausan (Critical jika sisa kesehatan <= 70%)
$ShowMetrics    =$false
$AgentRoot      = "$env:ProgramData\checkmk\agent"
$CacheDir       = "$AgentRoot\cache"
$CacheFile      = "$CacheDir\cache_disk_health.txt"
$CdiFile        = "$AgentRoot\log_custom\diskinfo.txt"
$CdiMaxAgeHours = 8$CacheMaxMins   = 60    # Refresh cache setiap 60 menit atau tepat pukul 16:00
# --------------------------------

if (-not (Test-Path $CacheDir)) { [void](New-Item -ItemType Directory -Force -Path$CacheDir) }

# Cek apakah cache masih valid
$Now = Get-Date
$NeedUpdate =$true
if (Test-Path $CacheFile) {$CacheItem = Get-Item $CacheFile$AgeMins = ($Now -$CacheItem.LastWriteTime).TotalMinutes
    if ($CacheItem.Length -gt 0 -and $AgeMins -lt$CacheMaxMins) {
        $NeedUpdate =$false
    }
}

if (-not $NeedUpdate) {
    Get-Content $CacheFile -ErrorAction SilentlyContinue
    exit
}

function Get-NormName {
    param([string]$s)
    if (-not $s) { return '' }
    return (($s -replace '[^A-Za-z0-9]', '').ToLower())
}

$disks = @()
$note  = ''
$seenDisks = @{}

# ---------- 1. smartctl (NVMe dan SATA) ----------
$smartctl = $null$cmd = Get-Command smartctl.exe -ErrorAction SilentlyContinue
if ($cmd) { $smartctl =$cmd.Source }
if (-not $smartctl) {
    foreach ($p in @(
        'C:\Program Files\smartmontools\bin\smartctl.exe',
        'C:\Program Files (x86)\smartmontools\bin\smartctl.exe'
    )) {
        if (Test-Path $p) { $smartctl =$p; break }
    }
}

if ($smartctl) {$targets = @()
    try {
        $scanRaw = & $smartctl --scan -j 2>$null
        if ($scanRaw) {
            $scan = ($scanRaw -join "`n") | ConvertFrom-Json
            if ($scan -and $scan.devices) {
                foreach ($sd in $scan.devices) {
                    $targets += [pscustomobject]@{ Name = $sd.name; Type = $sd.type }
                }
            }
        }
    } catch {}

    # Tambahkan fallback /dev/pd0..pd7 jika belum tercover --scan
    $wmiDisks = Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue
    foreach ($wd in $wmiDisks) {
        $pdName = "/dev/pd$($wd.Index)"
        if (-not ($targets | Where-Object { $_.Name -eq $pdName })) {
            $targets += [pscustomobject]@{ Name = $pdName; Type = '' }
        }
    }

    foreach ($t in $targets) {
        $json = $null
        try {
            $raw = if ($t.Type) { & $smartctl -j -a $t.Name -d $t.Type 2>$null } else { & $smartctl -j -a $t.Name 2>$null }
            if ($raw) { $json = ($raw -join "`n") | ConvertFrom-Json }
        } catch {}
        if (-not $json -or -not$json.smart_status) { continue }

        $model = if ($json.model_name) {$json.model_name.Trim() } else { 'Disk' }
        $serial = [string]$json.serial_number
        $dupKey = if ($serial) { "$(Get-NormName$model)|$($serial.Trim())" } else { "$(Get-NormName$model)|$($t.Name)" }
        if ($seenDisks.ContainsKey($dupKey)) { continue }$seenDisks[$dupKey] =$true

        $pohText = 'N/A'
        if ($json.power_on_time -and$json.power_on_time.hours) {
            $jam = [int]$json.power_on_time.hours
            $pohText = "$jam Jam ($([math]::Round($jam / 24)) Hari)"
        }

        $nvmeLog  =$json.nvme_smart_health_information_log
        $ataTable = @($json.ata_smart_attributes.table)

        if ($nvmeLog) {$health = 'Healthy'
            if ([int]$nvmeLog.critical_warning -ne 0) {$health = 'Warning' }
            if ($json.smart_status.passed -eq $false) {$health = 'Unhealthy' }

            $wear = [int]$nvmeLog.percentage_used
            $pct  = [math]::Max(0, 100 -$wear)

            $rwInfo = ''
            if ($null -ne $nvmeLog.data_units_read -and$null -ne $nvmeLog.data_units_written) {$rTB = [math]::Round(($nvmeLog.data_units_read * 512000) / 1TB, 2)$wTB = [math]::Round(($nvmeLog.data_units_written * 512000) / 1TB, 2)$rwInfo = " | R/W: ${rTB}/${wTB} TB"
            }

            $disks += [pscustomobject]@{
                Model   = $model
                Serial  = $serial
                Type    = 'NVMe'
                Health  = $health
                Display = "$health ($pct%)"
                Temp    = [int]$nvmeLog.temperature
                Wear    = $wear
                Poh     = $pohText
                Extra   = $rwInfo
                Source  = 'smartctl'
            }
        }
        elseif ($ataTable.Count -gt 0) {
            $isSsd =$true
            if ($null -ne $json.rotation_rate -and [int]$json.rotation_rate -gt 0) { $isSsd =$false }
            if ($ataTable \vert{} Where-Object {$_.name -match 'Spin_Up_Time' }) { $isSsd =$false }

            $temp =$null
            if ($null -ne$json.temperature -and $null -ne$json.temperature.current) {
                $temp = [int]$json.temperature.current
            } else {
                foreach ($a in$ataTable) {
                    if ($a.name -match 'Temperature' -and $null -ne$a.raw) {
                        $temp = [int]($a.raw.value -band 255); break
                    }
                }
            }

            $remain =$null
            if ($isSsd) {$attrH = $ataTable \vert{} Where-Object {$_.id -in @(169, 177, 202, 231, 232, 233) -or
                    $_.name -match 'Wearout|Life|Remaining|Endurance|Available_Reservd|Wear_Leveling'
                } | Select-Object -First 1

                if ($attrH) {
                    if ($attrH.id -eq 169 -and $attrH.raw.value -gt 0 -and$attrH.raw.value -le 100) {
                        $remain = [int]$attrH.raw.value
                    } elseif ([int]$attrH.value -gt 0 -and [int]$attrH.value -le 100) {
                        $remain = [int]$attrH.value
                    }
                }
            }

            $health = 'Healthy'$badSectors = 0
            foreach ($a in$ataTable) {
                if (($a.id -eq 5 -or$a.id -eq 197 -or $a.id -eq 198) -and$null -ne $a.raw -and [long]$a.raw.value -gt 0) {
                    $badSectors += [long]$a.raw.value
                    $health = 'Warning'
                }
            }
            if ($json.smart_status.passed -eq $false) {$health = 'Unhealthy' }

            $wear    =$null
            $display = if (-not$isSsd -and $badSectors -gt 0) { "Warning ($badSectors Bad Sector)" } else { $health }
            if ($null -ne $remain) {$wear    = [math]::Max(0, 100 - $remain)$display = "$health ($remain%)"
            }

            $tipe = if ($isSsd) { 'SSD SATA' } else { 'HDD SATA' }

            $disks += [pscustomobject]@{
                Model   = $model
                Serial  = $serial
                Type    = $tipe
                Health  = $health
                Display = $display
                Temp    = $temp
                Wear    = $wear
                Poh     = $pohText
                Extra   = ''
                Source  = 'smartctl'
            }
        }
    }
}

# ---------- 2. CrystalDiskInfo (diskinfo.txt) ----------
if (Test-Path $CdiFile) {
    $ageHours = ((Get-Date) - (Get-Item$CdiFile).LastWriteTime).TotalHours
    if ($ageHours -gt$CdiMaxAgeHours) {
        $note = ' [data CrystalDiskInfo kedaluwarsa, cek Task Checkmk_CrystalDiskInfo]'
    } else {
        $cdiList = @()
        $cur =$null
        foreach ($line in (Get-Content$CdiFile)) {
            if ($line -match '^\s*Model\s*:\s*(.+?)\s*$') {
                if ($cur) { $cdiList +=$cur }
                $cur = [pscustomobject]@{ Model =$Matches[1].Trim(); Serial = ''; Interface = ''; Rotation = ''; Temp = $null; Word = ''; Pct =$null; Poh = 'N/A' }
                continue
            }
            if (-not $cur) { continue }
            if ($line -match '^\s*Serial Number\s*:\s*(.+?)\s*$') {
                $cur.Serial =$Matches[1].Trim()
            } elseif ($line -match '^\s*Interface\s*:\s*(.+?)\s*$') {
                $cur.Interface =$Matches[1].Trim()
            } elseif ($line -match '^\s*Rotation Rate\s*:\s*(.+?)\s*$') {
                $cur.Rotation =$Matches[1].Trim()
            } elseif ($line -match '^\s*Power On Hours\s*:\s*(\d+)\s*') {
                $jam = [int]$Matches[1]
                $cur.Poh = "$jam Jam ($([math]::Round($jam / 24)) Hari)"
            } elseif ($line -match '^\s*Temperature\s*:\s*(-?\d+)\s*C') {$cur.Temp = [int]$Matches[1] } elseif ($line -match '^\s*Health Status\s*:\s*([A-Za-z]+)(?:\s*\((\d+)\s*\%\))?') {
                $cur.Word =$Matches[1]
                if ($Matches[2]) { $cur.Pct = [int]$Matches[2] }
            }
        }
        if ($cur) { $cdiList +=$cur }

        foreach ($c in$cdiList) {
            if ($c.Interface -notmatch 'NVM|ATA|RAID') { continue }
            $dupKey = if ($c.Serial) { "$(Get-NormName$c.Model)|$($c.Serial)" } else { "$(Get-NormName$c.Model)" }
            if ($seenDisks.ContainsKey($dupKey)) { continue }
            # Cek apakah model+serial sudah ada
            $already =$disks | Where-Object {
                ($c.Serial -and $_.Serial -eq$c.Serial) -or
                (-not $c.Serial -and (Get-NormName $_.Model) -eq (Get-NormName$c.Model))
            }
            if ($already) { continue }$seenDisks[$dupKey] =$true

            $tipe = 'SATA'
            if ($c.Interface -match 'NVM')        {$tipe = 'NVMe' }
            elseif ($c.Rotation -match 'SSD\vert{}^-+') {$tipe = 'SSD SATA' }
            elseif ($c.Rotation -match 'RPM')     {$tipe = 'HDD SATA' }
            elseif ($null -ne $c.Pct)             {$tipe = 'SSD SATA' }

            $health = 'Unknown'
            if ($c.Word -eq 'Good')    {$health = 'Healthy' }
            if ($c.Word -eq 'Caution') {$health = 'Warning' }
            if ($c.Word -eq 'Bad')     {$health = 'Unhealthy' }

            $wear =$null
            $display =$c.Word
            if ($null -ne $c.Pct) {$wear = [math]::Max(0, 100 - $c.Pct)$display = "$($c.Word) ($($c.Pct)%)"
            }
            if (-not $display) {$display = 'Unknown' }

            $disks += [pscustomobject]@{
                Model   = $c.Model
                Serial  = $c.Serial
                Type    = $tipe
                Health  = $health
                Display = $display
                Temp    = $c.Temp
                Wear    = $wear
                Poh     = $c.Poh
                Extra   = ''
                Source  = 'CrystalDiskInfo'
            }
        }
    }
}

# ---------- 3. Cadangan: data dari Windows Storage API ----------
$pds = @(Get-PhysicalDisk -ErrorAction SilentlyContinue \vert{} Where-Object { @('NVMe', 'SATA', 'ATA', 'SAS', 'SCSI', 'RAID') -contains [string]$_.BusType })
$winNvme  = @($pds | Where-Object { [string]$_.BusType -eq 'NVMe' -or [string]$_.BusType -eq 'RAID' }).Count
$winOther = $pds.Count -$winNvme

foreach ($pd in$pds) {
    $isNvme = ([string]$pd.BusType -eq 'NVMe' -or ([string]$pd.BusType -eq 'RAID' -and [string]$pd.MediaType -eq 'SSD'))
    $have = @($disks | Where-Object { ($_.Type -eq 'NVMe') -eq$isNvme }).Count
    $need = if ($isNvme) { $winNvme } else {$winOther }
    if ($have -ge$need -and $disks.Count -ge$pds.Count) { continue }

    $pdSerial = [string]$pd.SerialNumber
    $already =$disks | Where-Object {
        ($pdSerial -and$_.Serial -and $_.Serial.Trim() -eq$pdSerial.Trim()) -or
        ((Get-NormName $_.Model) -eq (Get-NormName$pd.FriendlyName) -and $disks.Count -ge$pds.Count)
    }
    if ($already) { continue }

    $rc =$null
    try { $rc =$pd | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue } catch {}

    $temp = $null$wear = $null$pohText = 'N/A'
    if ($rc) {
        if ($null -ne $rc.Temperature -and [int]$rc.Temperature -gt 0) { $temp = [int]$rc.Temperature }
        if ($null -ne$rc.Wear) { $wear = [int]$rc.Wear }
        if ($rc.PowerOnHours) {
            $jam = [int]$rc.PowerOnHours
            $pohText = "$jam Jam ($([math]::Round($jam / 24)) Hari)"
        }
    }

    $tipe = 'NVMe'
    if (-not $isNvme) {
        if ([string]$pd.MediaType -eq 'SSD') {$tipe = 'SSD SATA' }
        elseif ([string]$pd.MediaType -eq 'HDD') {$tipe = 'HDD SATA' }
        else { $tipe = 'SATA' }
    }

    $model = if ($pd.FriendlyName) { $pd.FriendlyName.Trim() } else {$tipe }
    $health = if ($pd.HealthStatus) { [string]$pd.HealthStatus } else { 'Unknown' }$display = if ($null -ne$wear) { "$health ($([math]::Max(0, 100 - $wear))\%)" } else { $health }

    $disks += [pscustomobject]@{
        Model   = $model
        Serial  = $pdSerial
        Type    = $tipe
        Health  = $health
        Display = $display
        Temp    = $temp
        Wear    = $wear
        Poh     = $pohText
        Extra   = ''
        Source  = 'Windows'
    }
}

$P = [char]124$outLines = @()

if ($disks.Count -eq 0) {$outLines += "0 `"Storage_Health`" - Tidak ada disk terdeteksi$note"
} else {
    $disks = @($disks \vert{} Sort-Object @{ Expression = { if ($_.Type -eq 'NVMe') { 0 } else { 1 } } }, Model)

    $i = 0
    foreach ($dk in$disks) {
        $i++$state = 0
        if ($dk.Health -eq 'Warning')   {$state = 1 }
        if ($dk.Health -eq 'Unhealthy') {$state = 2 }

        # Evaluasi suhu & keausan berlaku untuk semua sumber jika nilainya terbaca
        if ($null -ne$dk.Temp) {
            if ($dk.Temp -ge $CritTemp) {$state = 2 }
            elseif ($dk.Temp -ge$WarnTemp -and $state -lt 1) {$state = 1 }
        }
        if ($null -ne$dk.Wear) {
            if ($dk.Wear -ge $CritUsed) {$state = 2 }
            elseif ($dk.Wear -ge$WarnUsed -and $state -lt 1) {$state = 1 }
        }

        $tempText = if ($null -ne$dk.Temp) { "$($dk.Temp) C" } else { 'tidak tersedia' }
        $wearText = if ($null -ne$dk.Wear) { "$($dk.Wear)%" } else { 'tidak tersedia' }

        $metricList = @()
        if ($null -ne $dk.Temp) {$metricList += "temp=$($dk.Temp);$WarnTemp;$CritTemp" }
        if ($null -ne $dk.Wear) {$metricList += "wear=$($dk.Wear);$WarnUsed;$CritUsed;0;100" }

        $metrics = '-'
        if ($ShowMetrics -and $metricList.Count -gt 0) {$metrics = $metricList -join "$P" }

        $name = if ($i -eq 1) { 'Storage_Health' } else { "Storage_Health $i" }

        $text = "$($dk.Model)$P Tipe: $($dk.Type) $P Status:$($dk.Display)$P Suhu: $tempText$P Masa Pakai: $($dk.Poh)"
        if ($dk.Type -ne 'HDD SATA') {$text += " $P Keausan:$wearText" }
        if ($dk.Extra) { $text +=$dk.Extra }
        if ($dk.Source -ne 'smartctl') {$text += " [sumber: $($dk.Source)]" }
        if ($dk.Source -eq 'Windows') {$text += $note }

        $outLines += ('{0} "{1}" {2} {3}' -f $state,$name, $metrics,$text)
    }
}

$outLines \vert{} Set-Content -Path$CacheFile -Encoding ASCII -Force
Get-Content $CacheFile -ErrorAction SilentlyContinue

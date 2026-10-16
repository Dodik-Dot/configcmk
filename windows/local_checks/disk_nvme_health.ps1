# ==========================================================
# disk_nvme_health.ps1 - Checkmk Local Check (Windows)
# Format Service: Storage_Health_<Merk>
# ==========================================================
$ErrorActionPreference = 'SilentlyContinue'

$WarnTemp       = 60$CritTemp       = 70
$WarnUsed       = 15$CritUsed       = 30
$ShowMetrics    =$false
$AgentRoot      = "$env:ProgramData\checkmk\agent"
$CacheDir       = "$AgentRoot\cache"
$CacheFile      = "$CacheDir\cache_disk_health.txt"
$CdiFile        = "$AgentRoot\log_custom\diskinfo.txt"
$CdiMaxAgeHours = 8$CacheMaxMins   = 60

if (-not (Test-Path $CacheDir)) { [void](New-Item -ItemType Directory -Force -Path$CacheDir) }

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

        $model = if ($json.model_name) {$json.model_name.Trim() } else { 'Unknown Disk' }
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

        if ($nvmeLog) {$health = 'PASSED'
            if ([int]$nvmeLog.critical_warning -ne 0) {$health = 'WARNING' }
            if ($json.smart_status.passed -eq $false) {$health = 'FAILED' }

            $wear = [int]$nvmeLog.percentage_used
            $sisaHealth = [math]::Max(0, 100 -$wear)

            $rTB = 0; $wTB = 0; $estMaxTbw = 'N/A';$prediksi = 'N/A'
            if ($null -ne$nvmeLog.data_units_read -and $null -ne$nvmeLog.data_units_written) {
                $rTB = [math]::Round(($nvmeLog.data_units_read * 512000) / 1TB, 2)
                $wTB = [math]::Round(($nvmeLog.data_units_written * 512000) / 1TB, 2)
            }

            if ($wTB -gt 0 -and $wear -gt 0) {$tbwCalc = [math]::Round(($wTB / $wear) * 100, 1)
                $estMaxTbw = "$tbwCalc TB"
            }

            if ($json.power_on_time.hours -and$wear -gt 0) {
                $sisaJam = ($json.power_on_time.hours / $wear) *$sisaHealth
                $sisaHari = [math]::Round($sisaJam / 24)
                if ($sisaHari -gt 365) {$prediksi = "Sekitar $([math]::Round($sisaHari / 365, 1)) Tahun"
                } else {
                    $prediksi = "Sekitar $sisaHari Hari"
                }
            }

            $disks += [pscustomobject]@{
                Model     = $model
                Serial    = $serial
                Type      = 'NVME'
                HealthTxt = $health
                Kesehatan = "$sisaHealth%"
                Temp      = "$([int]$nvmeLog.temperature) Celcius"
                Poh       = $pohText
                Read      = "$rTB TB"
                Write     = "$wTB TB"
                MaxTbw    = $estMaxTbw
                Prediksi  = $prediksi
                Wear      = $wear
                Source    = 'smartctl'
            }
        }
        elseif ($ataTable.Count -gt 0) {
            $isSsd =$true
            if ($null -ne $json.rotation_rate -and [int]$json.rotation_rate -gt 0) { $isSsd =$false }
            if ($ataTable \vert{} Where-Object {$_.name -match 'Spin_Up_Time' }) { $isSsd =$false }

            $tempVal =$null
            if ($null -ne$json.temperature -and $null -ne$json.temperature.current) {
                $tempVal = [int]$json.temperature.current
            } else {
                foreach ($a in$ataTable) {
                    if ($a.name -match 'Temperature' -and $null -ne$a.raw) {
                        $tempVal = [int]($a.raw.value -band 255); break
                    }
                }
            }
            $tempTxt = if ($null -ne $tempVal) { "$tempVal Celcius" } else { "? Celcius" }

            $sisaHealth = 100
            if ($isSsd) {$attrH = $ataTable \vert{} Where-Object {$_.id -in @(169, 177, 202, 231, 232, 233) -or
                    $_.name -match 'Wearout|Life|Remaining|Endurance|Available_Reservd|Wear_Leveling'
                } | Select-Object -First 1

                if ($attrH) {
                    if ($attrH.id -eq 169 -and $attrH.raw.value -gt 0 -and$attrH.raw.value -le 100) {
                        $sisaHealth = [int]$attrH.raw.value
                    } elseif ([int]$attrH.value -gt 0 -and [int]$attrH.value -le 100) {
                        $sisaHealth = [int]$attrH.value
                    }
                }
            }

            $health = 'PASSED'$badSectors = 0
            foreach ($a in$ataTable) {
                if (($a.id -eq 5 -or$a.id -eq 197 -or $a.id -eq 198) -and$null -ne $a.raw -and [long]$a.raw.value -gt 0) {
                    $badSectors += [long]$a.raw.value
                    $health = 'WARNING'
                }
            }
            if ($json.smart_status.passed -eq $false) {$health = 'FAILED' }

            $tipe = if ($isSsd) { 'SSD Sata' } else { 'HDD (Mekanik)' }
            $wear = 100 -$sisaHealth

            $disks += [pscustomobject]@{
                Model     = $model
                Serial    = $serial
                Type      = $tipe
                HealthTxt = $health
                Kesehatan = "$sisaHealth%"
                Temp      = $tempTxt
                Poh       = $pohText
                Read      = 'N/A'
                Write     = 'N/A'
                MaxTbw    = 'N/A'
                Prediksi  = 'N/A'
                Wear      = $wear
                Source    = 'smartctl'
            }
        }
    }
}

# ---------- 2. CrystalDiskInfo (diskinfo.txt) ----------
if (Test-Path $CdiFile) {
    $ageHours = ((Get-Date) - (Get-Item$CdiFile).LastWriteTime).TotalHours
    if ($ageHours -le $CdiMaxAgeHours) {$cdiList = @()
        $cur =$null
        foreach ($line in (Get-Content$CdiFile)) {
            if ($line -match '^\s*Model\s*:\s*(.+?)\s*$') {
                if ($cur) { $cdiList +=$cur }
                $cur = [pscustomobject]@{ Model =$Matches[1].Trim(); Serial = ''; Interface = ''; Rotation = ''; Temp = 'N/A'; Word = 'PASSED'; Pct = 100; Poh = 'N/A' }
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
            } elseif ($line -match '^\s*Temperature\s*:\s*(-?\d+)\s*C') {$cur.Temp = "$($Matches[1]) Celcius"
            } elseif ($line -match '^\s*Health Status\s*:\s*([A-Za-z]+)(?:\s*\((\d+)\s*\%\))?') {
                $word =$Matches[1]
                if ($word -eq 'Caution') {$cur.Word = 'WARNING' }
                elseif ($word -eq 'Bad') {$cur.Word = 'FAILED' }
                else { $cur.Word = 'PASSED' }
                if ($Matches[2]) { $cur.Pct = [int]$Matches[2] }
            }
        }
        if ($cur) { $cdiList +=$cur }

        foreach ($c in$cdiList) {
            if ($c.Interface -notmatch 'NVM|ATA|RAID') { continue }
            $dupKey = if ($c.Serial) { "$(Get-NormName$c.Model)|$($c.Serial)" } else { "$(Get-NormName$c.Model)" }
            if ($seenDisks.ContainsKey($dupKey)) { continue }$seenDisks[$dupKey] =$true

            $tipe = 'SSD/NVMe'
            if ($c.Interface -match 'NVM') {$tipe = 'NVME' }
            elseif ($c.Rotation -match 'RPM') {$tipe = 'HDD (Mekanik)' }

            $wear = 100 -$c.Pct

            $disks += [pscustomobject]@{
                Model     = $c.Model
                Serial    = $c.Serial
                Type      = $tipe
                HealthTxt = $c.Word
                Kesehatan = "$($c.Pct)%"
                Temp      = $c.Temp
                Poh       = $c.Poh
                Read      = 'N/A'
                Write     = 'N/A'
                MaxTbw    = 'N/A'
                Prediksi  = 'N/A'
                Wear      = $wear
                Source    = 'CrystalDiskInfo'
            }
        }
    }
}

$P = [char]124$outLines = @()

if ($disks.Count -eq 0) {$outLines += "0 `"Storage_Health_Unknown`" - Status : PASSED $P Drive: N/A $P Merk: Tidak Ada Disk$P Kesehatan: N/A"
} else {
    $disks = @($disks \vert{} Sort-Object @{ Expression = { if ($_.Type -eq 'NVME') { 0 } else { 1 } } }, Model)

    foreach ($dk in $disks) {$state = 0
        if ($dk.HealthTxt -eq 'WARNING') {$state = 1 }
        if ($dk.HealthTxt -eq 'FAILED')  {$state = 2 }

        # Bersihkan nama merk dari karakter khusus untuk nama service Checkmk
        $cleanMerk =$dk.Model -replace '[^\w\s-]', '' -replace '\s+', '_'

        $name = "Storage_Health_$cleanMerk"

        $text = "Status : $($dk.HealthTxt) $P Drive:$($dk.Type)$P Merk: $($dk.Model) $P Kesehatan:$($dk.Kesehatan)$P Suhu: $($dk.Temp) $P Masa Pakai:$($dk.Poh)$P Read: $($dk.Read) $P Write:$($dk.Write)$P Est Max TBW: $($dk.MaxTbw) $P Prediksi:$($dk.Prediksi)$P SMART: $($dk.HealthTxt)"

        $outLines += ('{0} "{1}" - {2}' -f $state, $name,$text)
    }
}

$outLines \vert{} Set-Content -Path$CacheFile -Encoding ASCII -Force
Get-Content $CacheFile -ErrorAction SilentlyContinue

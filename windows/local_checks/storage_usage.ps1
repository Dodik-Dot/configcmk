# =====================================================================
# Local Check Checkmk: Daily Physical Disk & NVMe SMART Health (Windows)
# Scheduled to run once a day at 16:00
# =====================================================================
$ErrorActionPreference = 'SilentlyContinue'
$CacheDir = "$env:ProgramData\checkmk\agent\cache"
if (-not (Test-Path $CacheDir)) { New-Item -ItemType Directory -Force $CacheDir | Out-Null }
$CacheFile = Join-Path $CacheDir "cache_disk_nvme_health.txt"

# Logika Penjadwalan: Eksekusi Baru Setiap Hari Setelah Pukul 16:00
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
    $Lines = [System.Collections.Generic.List[string]]::new()
    $SmartctlPath = "C:\Program Files\smartmontools\bin\smartctl.exe"

    if (Test-Path $SmartctlPath) {
        # 1. Deteksi seluruh drive dan parameter device (-d nvme / -d ata) secara dinamis
        $ScanLines = & $SmartctlPath --scan 2>$null
        $TargetDevices = @()

        foreach ($line in $ScanLines) {
            if ($line -match '^(\S+)\s+(.*?)\s*#') {
                $dev = $Matches[1].Trim()
                $args = $Matches[2].Trim()
                $TargetDevices += [PSCustomObject]@{
                    Device = $dev
                    Params = ($args -split '\s+')
                }
            }
        }

        # Fallback jika scan tidak mengembalikan device
        if ($TargetDevices.Count -eq 0) {
            $TargetDevices += [PSCustomObject]@{ Device = "/dev/sda"; Params = @("-d", "nvme") }
            $TargetDevices += [PSCustomObject]@{ Device = "/dev/pd0"; Params = @() }
        }

        foreach ($tgt in $TargetDevices) {
            $cmdArgs = @("-j", "-a", $tgt.Device) + $tgt.Params
            $jsonStr = & $SmartctlPath $cmdArgs 2>&1 | Out-String
            $drive = $jsonStr | ConvertFrom-Json -ErrorAction SilentlyContinue

            if (-not $drive -or -not $drive.model_name) { continue }

            $Model = $drive.model_name.Trim()
            $CleanModel = ($Model -replace '[^\w\s-]', '' -replace '\s+', ' ').Trim()
            $ServiceName = "Storage_Health_$CleanModel"

            # Kapasitas Drive
            $SizeGB = 0
            if ($drive.user_capacity.bytes) {
                $SizeGB = [Math]::Round($drive.user_capacity.bytes / 1GB, 2)
            }

            # SMART Status & Suhu
            $Passed = $drive.smart_status.passed
            $SmartStatus = if ($Passed) { "PASSED" } else { "FAILED" }
            $StatusCode = if ($Passed) { 0 } else { 2 }

            $Temp = if ($drive.temperature.current) { "$($drive.temperature.current)C" } else { "N/A" }
            
            # POH (Power On Hours)
            $POH = if ($drive.power_on_time.hours) { $drive.power_on_time.hours } else { 0 }

            $HealthPct = "100%"
            $ReadTB = "0 TB"
            $WrittenTB = "0 TB"
            $WritePerDay = "N/A"
            $DriveType = "HDD/SATA"

            # 2. Pembacaan Spesifik Protokol NVMe
            if ($drive.nvme_smart_health_information_log) {
                $DriveType = "NVME"
                $nvme = $drive.nvme_smart_health_information_log

                # Perhitungan Health NVMe (100% - Percentage Used)
                if ($null -ne $nvme.percentage_used) {
                    $wear = [int]$nvme.percentage_used
                    $calcHealth = 100 - $wear
                    $HealthPct = "$calcHealth%"
                    if ($calcHealth -le 20) { $StatusCode = 2 }
                    elseif ($calcHealth -le 50) { $StatusCode = 1 }
                }

                # 1 Data Unit = 512.000 Bytes (Spesifikasi Standar NVMe)
                if ($nvme.data_units_read) {
                    $rBytes = [double]$nvme.data_units_read * 512000
                    $ReadTB = "$([Math]::Round($rBytes / 1TB, 2)) TB"
                }
                if ($nvme.data_units_written) {
                    $wBytes = [double]$nvme.data_units_written * 512000
                    $wTB = [Math]::Round($wBytes / 1TB, 2)
                    $WrittenTB = "$wTB TB"

                    if ($POH -gt 0) {
                        $days = $POH / 24
                        if ($days -ge 1) {
                            $dailyGB = [Math]::Round(($wBytes / 1GB) / $days, 2)
                            $WritePerDay = "$dailyGB GB/Day"
                        }
                    }
                }
            } 
            # 3. Pembacaan Drive SATA / HDD
            elseif ($drive.ata_smart_attributes.table) {
                $wearAttr = $drive.ata_smart_attributes.table | Where-Object { $_.name -match "Wearout|Life|Remaining|Endurance" } | Select-Object -First 1
                if ($wearAttr) {
                    $HealthPct = "$($wearAttr.value)%"
                    $DriveType = "SSD SATA"
                }
            }

            $StatusTxt = switch ($StatusCode) { 0 { "OK" } 1 { "WARNING" } 2 { "CRITICAL" } }
            $OutputLine = "$StatusCode `"$ServiceName`" - Status : $StatusTxt | Model: $Model ($SizeGB GB) | Status: $SmartStatus | Temp: $Temp | Type: $DriveType ($SizeGB GB) | Health: $HealthPct | Read: $ReadTB | Written: $WrittenTB | Write/Day: $WritePerDay"
            $Lines.Add($OutputLine)
        }
    } else {
        $Lines.Add("1 `"Storage_Health`" - smartmontools tidak ditemukan di $SmartctlPath")
    }

    [System.IO.File]::WriteAllLines($CacheFile, $Lines, [System.Text.Encoding]::UTF8)
}

if (Test-Path $CacheFile) {
    [System.IO.File]::ReadAllLines($CacheFile, [System.Text.Encoding]::UTF8)
}

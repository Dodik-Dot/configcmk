# =====================================================================
# Local Check Checkmk: Smartctl Storage Health Monitor (Windows)
# Engine: smartctl.exe JSON Parser + Intel VMD Bypass via Intel MAS CLI
# Scheduled to run once a day at 16:00
# =====================================================================
$ErrorActionPreference = 'SilentlyContinue'
$CacheDir  = "$env:ProgramData\checkmk\agent\cache"
if (-not (Test-Path $CacheDir)) { New-Item -ItemType Directory -Force$CacheDir | Out-Null }
$CacheFile = Join-Path$CacheDir "cache_disk_health.txt"

# 1. Logika Penjadwalan Cache Harian Pukul 16:00
$Now = Get-Date
$Today16 = Get-Date -Hour 16 -Minute 0 -Second 0$Last16  = if ($Now -lt$Today16) { $Today16.AddDays(-1) } else {$Today16 }

$NeedUpdate =$true
if (Test-Path $CacheFile) {
    $CacheMtime = (Get-Item$CacheFile).LastWriteTime
    if ($CacheMtime -ge$Last16) {
        $NeedUpdate =$false
    }
}

if ($NeedUpdate) {
    if (Test-Path $CacheFile) { Remove-Item$CacheFile -Force }

    $SmartctlBin = "C:\Program Files\smartmontools\bin\smartctl.exe"
    if (-not (Test-Path $SmartctlBin)) {$CmdCheck = Get-Command smartctl.exe -ErrorAction SilentlyContinue
        if ($CmdCheck) { $SmartctlBin =$CmdCheck.Source }
    }

    $disks = Get-WmiObject Win32_DiskDrive -ErrorAction SilentlyContinue

    foreach ($disk in$disks) {
        $i =$disk.Index
        $merk = if ($disk.Model) {$disk.Model.Trim() } else { "Model_Tidak_Diketahui" }
        
        $json_raw =$null
        if ($SmartctlBin) {
            $json_raw = &$SmartctlBin -j -a "/dev/pd$i" 2>$null
        }
        
        $drive =$null
        if ($json_raw) { $drive =$json_raw | ConvertFrom-Json }

        # ====================================================================
        # FALLBACK INTEL VMD: Jika smartctl gagal atau terhalang VMD
        # ====================================================================
        if (-not $drive -or -not $drive.smart_status) {$masPath = "C:\Program Files\Intel\Intel(R) Memory and Storage Tool\intelmas.exe"
            
            if (Test-Path $masPath) {$masOutput = & $masPath show -smart 2>$null
                
                if ($masOutput -match "PercentageUsed" -or $masOutput -match "AvailableSpare") {
                    $health = 100$temp = 0
                    
                    foreach ($line in$masOutput) {
                        if ($line -match "PercentageUsed\s+:\s+(\d+)") { 
                            $health = 100 - [int]$matches[1] 
                        }
                        if ($line -match "Temperature\s+:\s+(\d+)") { 
                            $temp = "$([int]$matches[1]) Celcius"
                        }
                    }
                    
                    $kode = 0
                    if ($health -le 70) {$kode = 2 } elseif ($health -le 85) {$kode = 1 }
                    
                    $detail = "Drive: SSD/NVMe (VMD) \vert{} Merk: $merk | Kesehatan: $health\% \vert{} Suhu:$temp | Total Dipakai: N/A | Prediksi: Berdasarkan Wear Leveling | SMART: PASSED"
                    $CleanMerk =$merk -replace '[^\w\s-]', ''
                    $outputLine = "$kode `"Storage_Health_$CleanMerk`" - Status : OK | $detail"
                    $outputLine \vert{} Out-File -FilePath$CacheFile -Encoding utf8 -Append
                }
            }
            continue
        }

        # ====================================================================
        # NORMAL SMARTCTL PROCESSING (SATA / Native NVMe)
        # ====================================================================
        if ($drive.model_name) { $merk =$drive.model_name.Trim() }

        # 2. Status SMART Dasar
        $is_passed =$drive.smart_status.passed
        if ($is_passed) { $status = "PASSED"; $kode = 0 } else { $status = "FAILED"; $kode = 2 }

        # 3. Suhu & Jam Operasional (POH)
        $temp = if ($drive.temperature.current) { "$($drive.temperature.current) Celcius" } else { "? Celcius" }
        $jam = 0
        if ($drive.power_on_time.hours) {
            $jam = [int]$drive.power_on_time.hours
            $hari_poh = [math]::Round($jam / 24)$poh = "$jam Jam ($hari_poh Hari)"
        } else { $poh = "Tidak terbaca" }

        # 4. Deteksi Tipe Drive (HDD Mekanik vs SSD)
        $is_hdd =$false
        if ($drive.rotation_rate -and$drive.rotation_rate -gt 0) { $is_hdd =$true }
        if ($drive.ata_smart_attributes.table) {$spin_up = $drive.ata_smart_attributes.table \vert{} Where-Object {$_.name -match "Spin_Up_Time" }
            if ($spin_up) { $is_hdd =$true }
        }

        if ($is_hdd) {
            # === MODE HARDDISK MEKANIK ===
            $tipe = "HDD (Mekanik)"
            $bad_sectors = 0
            if ($drive.ata_smart_attributes.table) {
                $realloc =$drive.ata_smart_attributes.table | Where-Object { $_.name -match "Reallocated_Sector" -or $_.name -match "Pending_Sector" }
                foreach ($item in$realloc) { $bad_sectors += [int]$item.raw.value }
            }
            
            if ($bad_sectors -gt 0) {
                $health_pct = "WARNING ($bad_sectors Bad Sector)"
                if ($kode -eq 0) { $kode = 1 }             } else {$health_pct = "Sehat (0 Bad Sector)"
            }
            $estimasi_umur = "Tidak bisa dihitung (HDD dinilai dari Bad Sector)"
            $detail = "Drive: $tipe | Merk: $merk \vert{} Kesehatan:$health_pct | Suhu: $temp \vert{} Total Dipakai:$poh | Prediksi: $estimasi_umur \vert{} SMART:$status"
        } 
        else {
            # === MODE SSD / NVMe ===
            $tipe = "SSD/NVMe"
            $health_pct = "Tidak terbaca"
            $sisa_health = 100
            $wear_terpakai = 0$total_read = "N/A"
            $total_write = "N/A"
            $max_tbw = "N/A"

            # A. KASUS 1: NVMe Native
            if ($drive.nvme_smart_health_information_log) {$tipe = "NVME"
                $wear_terpakai = [int]$drive.nvme_smart_health_information_log.percentage_used
                $sisa_health = [Math]::Max(0, (100 -$wear_terpakai))
                $health_pct = "$sisa_health%"
                if ($sisa_health -le 70) {$kode = 2 } elseif ($sisa_health -le 85) {$kode = 1 }
                
                $r_units =$drive.nvme_smart_health_information_log.data_units_read
                $w_units =$drive.nvme_smart_health_information_log.data_units_written
                if ($null -ne$r_units) { $total_read = [math]::Round(($r_units * 512000) / 1TB, 2) }
                if ($null -ne$w_units) { $total_write = [math]::Round(($w_units * 512000) / 1TB, 2) }
            } 
            # B. KASUS 2: SATA SSD
            elseif ($drive.ata_smart_attributes.table) {$tipe = "SSD Sata"
                $table =$drive.ata_smart_attributes.table

                $attrHealth = $table \vert{} Where-Object {$_.id -in @(169, 231, 202, 177, 232, 233) -or 
                    $_.name -match "Wearout|Life|Remaining|Endurance|Available_Reservd"
                } | Select-Object -First 1

                if ($attrHealth) {
                    if ($attrHealth.id -eq 169 -and $attrHealth.raw.value -gt 0 -and$attrHealth.raw.value -le 100) {
                        $sisa_health = [int]$attrHealth.raw.value
                    } else {
                        $sisa_health = [int]$attrHealth.value
                    }
                    $wear_terpakai = [Math]::Max(0, (100 -$sisa_health))
                    $health_pct = "$sisa_health%"
                    if ($sisa_health -le 70) {$kode = 2 } elseif ($sisa_health -le 85) {$kode = 1 }
                }

                $lba = if ($drive.logical_block_size) { [double]$drive.logical_block_size } else { 512.0 }
                $attr_read  =$table | Where-Object { $_.id -eq 242 -or$_.name -match "Total_LBAs_Read" } | Select-Object -First 1
                $attr_write =$table | Where-Object { $_.id -eq 241 -or$_.name -match "Total_LBAs_Written" } | Select-Object -First 1

                if ($attr_write) {
                    $rawValW = [double]$attr_write.raw.value
                    if ($rawValW -gt 10000000) {$total_write = [math]::Round(($rawValW * $lba) / 1TB, 2)
                    } else {
                        $total_write = [math]::Round(($rawValW * 1GB) / 1TB, 2)
                    }
                }

                if ($attr_read) {
                    $rawValR = [double]$attr_read.raw.value
                    if ($rawValR -gt 10000000) {$total_read = [math]::Round(($rawValR * $lba) / 1TB, 2)
                    } else {
                        $total_read = [math]::Round(($rawValR * 1GB) / 1TB, 2)
                    }
                }
            }

            if (($total_write -ne "N/A") -and ($wear_terpakai -gt 0) -and ($total_write -gt 0)) {$tbw_calc = [math]::Round(($total_write / $wear_terpakai) * 100, 2)
                $max_tbw = "$tbw_calc TB"
            } else {
                $max_tbw = "Tidak diketahui"
            }

            $str_read  = if ($total_read -ne "N/A") { "$total_read TB" } else { "N/A" }
            $str_write = if ($total_write -ne "N/A") { "$total_write TB" } else { "N/A" }

            $estimasi_umur = "Tidak dapat diprediksi"
            if ($jam -gt 0 -and$health_pct -ne "Tidak terbaca") {
                if ($wear_terpakai -gt 0) {
                    $sisa_jam = ($jam / $wear_terpakai) *$sisa_health
                    $sisa_hari = [math]::Round($sisa_jam / 24)
                    if ($sisa_hari -gt 365) {
                        $sisa_tahun = [math]::Round(($sisa_hari / 365), 1)
                        $estimasi_umur = "Sekitar $sisa_tahun Tahun"
                    } else {
                        $estimasi_umur = "Sekitar $sisa_hari Hari"
                    }
                } else {
                    $estimasi_umur = "Masih 100% (Sangat Panjang)"
                }
            }

            $detail = "Drive: $tipe \vert{} Merk:$merk | Kesehatan: $health_pct \vert{} Suhu:$temp | Masa Pakai: $poh \vert{} Read:$str_read | Write: $str_write \vert{} Est Max TBW:$max_tbw | Prediksi: $estimasi_umur \vert{} SMART:$status"
        }

        # Format Nama Service Checkmk
        $CleanMerk =$merk -replace '[^\w\s-]', ''
        $outputLine = "$kode `"Storage_Health_$CleanMerk`" - Status : OK | $detail"
        $outputLine \vert{} Out-File -FilePath$CacheFile -Encoding utf8 -Append
    }
}

Get-Content $CacheFile -ErrorAction SilentlyContinue

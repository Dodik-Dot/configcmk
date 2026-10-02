# =====================================================================
# Local Check Checkmk: Smartctl Storage Health Monitor (Windows)
# Engine: smartctl.exe JSON Parser + Intel VMD Bypass via Intel MAS CLI
# Scheduled to run once a day at 16:00
# =====================================================================
$ErrorActionPreference = 'SilentlyContinue'
$CacheDir = "$env:ProgramData\checkmk\agent\cache"

if ((Test-Path -Path $CacheDir) -eq$false) {
    $null = New-Item -ItemType Directory -Force -Path$CacheDir
}

$CacheFile = Join-Path -Path$CacheDir -ChildPath "cache_disk_health.txt"
if (Test-Path -Path $CacheFile) {
    Remove-Item -Path $CacheFile -Force
}

$SmartctlBin = "C:\Program Files\smartmontools\bin\smartctl.exe"
if ((Test-Path -Path $SmartctlBin) -eq $false) {$CmdCheck = Get-Command smartctl.exe -ErrorAction SilentlyContinue
    if ($CmdCheck) {
        $SmartctlBin =$CmdCheck.Source
    }
}

$disks = Get-WmiObject Win32_DiskDrive -ErrorAction SilentlyContinue

if ($disks) {
    foreach ($disk in$disks) {
        $i =$disk.Index
        $merk = "Model_Tidak_Diketahui"
        if ($disk.Model) {
            $merk =$disk.Model.Trim()
        }

        $json_raw =$null
        if ($SmartctlBin) {
            $json_raw = &$SmartctlBin -j -a "/dev/pd$i" 2>$null
        }

        $drive =$null
        if ($json_raw) {
            $drive = ConvertFrom-Json -InputObject$json_raw
        }

        # ====================================================================
        # FALLBACK INTEL VMD: Jika smartctl gagal atau terhalang VMD
        # ====================================================================
        if ((-not $drive) -or (-not $drive.smart_status)) {$masPath = "C:\Program Files\Intel\Intel(R) Memory and Storage Tool\intelmas.exe"

            if (Test-Path -Path $masPath) {$masOutput = & $masPath show -smart 2>$null

                if (($masOutput -match "PercentageUsed") -or ($masOutput -match "AvailableSpare")) {
                    $health = 100$temp = 0

                    foreach ($line in$masOutput) {
                        if ($line -match "PercentageUsed\s+:\s+(\d+)") {
                            $health = 100 - [int]$matches[1]
                        }
                        if ($line -match "Temperature\s+:\s+(\d+)") {
                            $temp = [int]$matches[1]
                        }
                    }

                    $kode = 0
                    if ($health -le 70) {$kode = 2 } elseif ($health -le 85) {$kode = 1 }

                    $detail = "Drive: SSD/NVMe (VMD) - Merk: $merk - Kesehatan: $health\% - Suhu:$temp Celcius - SMART: PASSED"
                    $CleanMerk =$merk -replace '[^\w\s-]', ''
                    
                    # Menggunakan [char]124 untuk memanggil garis lurus (pipe) agar tidak rusak saat copy-paste
                    $perf = "health=$health;85;70" + [char]124 + "temp=$temp;60;75"
                    $outputLine = "$kode `"Storage_Health_$CleanMerk`" $perf$detail"
                    
                    Add-Content -Path $CacheFile -Value$outputLine -Encoding UTF8
                }
            }
            continue
        }

        # ====================================================================
        # NORMAL SMARTCTL PROCESSING (SATA / Native NVMe)
        # ====================================================================
        if ($drive.model_name) {
            $merk =$drive.model_name.Trim()
        }

        $is_passed =$drive.smart_status.passed
        $status = "FAILED"
        $kode = 2
        if ($is_passed) {$status = "PASSED"
            $kode = 0
        }

        $temp = 0
        if ($drive.temperature.current) {
            $temp = [int]$drive.temperature.current
        }

        $wear_terpakai = 0
        if ($drive.nvme_smart_health_information_log) {
            $wear_terpakai = [int]$drive.nvme_smart_health_information_log.percentage_used
        }

        $sisa_health = [Math]::Max(0, (100 -$wear_terpakai))
        if ($sisa_health -le 70) {$kode = 2 } elseif ($sisa_health -le 85) {$kode = 1 }

        $detail = "Drive: SSD/NVMe Native - Merk: $merk - Kesehatan:$sisa_health% - Suhu: $temp Celcius - SMART:$status"
        $CleanMerk =$merk -replace '[^\w\s-]', ''
        
        # Menggunakan [char]124 untuk memanggil garis lurus (pipe)
        $perf = "health=$sisa_health;85;70" + [char]124 + "temp=$temp;60;75"
        $outputLine = "$kode `"Storage_Health_$CleanMerk`" $perf$detail"
        
        Add-Content -Path $CacheFile -Value$outputLine -Encoding UTF8
    }
}

Get-Content -Path $CacheFile -ErrorAction SilentlyContinue

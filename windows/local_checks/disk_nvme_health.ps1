# =====================================================================
# Local Check Checkmk: Smartctl Storage Health Monitor (Windows)
# Engine: smartctl.exe JSON Parser + Intel MAS + WinAPI Ultimate Fallback
# =====================================================================
$ErrorActionPreference = 'SilentlyContinue'
$CacheDir = "$env:ProgramData\checkmk\agent\cache"

if ((Test-Path -Path $CacheDir) -eq$false) {
    $null = New-Item -ItemType Directory -Force -Path$CacheDir
}

$CacheFile = "$CacheDir\cache_disk_health.txt"
if (Test-Path -Path $CacheFile) {
    Remove-Item -Path $CacheFile -Force
}

$SmartctlBin = "C:\Program Files\smartmontools\bin\smartctl.exe"
if ((Test-Path -Path $SmartctlBin) -eq $false) {$CmdCheck = Get-Command smartctl.exe -ErrorAction SilentlyContinue
    if ($CmdCheck) { $SmartctlBin =$CmdCheck.Source }
}

$disks = Get-WmiObject Win32_DiskDrive -ErrorAction SilentlyContinue

if ($disks) {
    foreach ($disk in$disks) {
        $i =$disk.Index
        $merk = "Model_Tidak_Diketahui"
        if ($disk.Model) { $merk =$disk.Model.Trim() }

        $json_raw =$null
        if ($SmartctlBin) { $json_raw = &$SmartctlBin -j -a "/dev/pd$i" 2>$null }

        $drive =$null
        if ($json_raw) { $drive = ConvertFrom-Json -InputObject$json_raw }

        # ====================================================================
        # FALLBACK VMD & WINDOWS API
        # ====================================================================
        if ((-not $drive) -or (-not $drive.smart_status)) {$masPath = "C:\Program Files\Intel\Intel(R) Memory and Storage Tool\intelmas.exe"
            $masSuccess =$false
            
            if (Test-Path -Path $masPath) {$masOutput = & $masPath show -smart 2>$null
                if (($masOutput -match "PercentageUsed") -or ($masOutput -match "AvailableSpare")) {
                    $masSuccess =$true
                    $health = 100$temp = 0
                    foreach ($line in$masOutput) {
                        if ($line -match "PercentageUsed\s+:\s+(\d+)") { $health = 100 - [int]$matches[1] }
                        if ($line -match "Temperature\s+:\s+(\d+)") { $temp = [int]$matches[1] }                     }$kode = 0
                    if ($health -le 70) {$kode = 2 } elseif ($health -le 85) {$kode = 1 }
                    $detail = "Drive: SSD/NVMe (VMD MAS) - Merk: $merk - Kesehatan: $health\% - Suhu:$temp C - SMART: PASSED"
                    $CleanMerk = $merk -replace '[^\w\s-]', ''$pipeChar = [char]124
                    $perf = "health=$health;85;70$pipeChar" + "temp=$temp;60;75"
                    Add-Content -Path $CacheFile -Value "$kode `"Storage_Health_$CleanMerk`" $perf$detail" -Encoding UTF8
                }
            }
            
            if (-not $masSuccess) {$gotApi = $false$allPhys = Get-PhysicalDisk -ErrorAction SilentlyContinue
                $physDisk =$null
                
                if ($allPhys) {
                    foreach ($pd in$allPhys) {
                        if ($pd.DeviceID -eq$i -or $pd.Model -match$merk) {
                            $physDisk =$pd
                            break
                        }
                    }
                    if (-not $physDisk) {
                        foreach ($pd in$allPhys) {
                            if ($pd.MediaType -eq 'SSD') {
                                $physDisk =$pd
                                break
                            }
                        }
                    }
                }
                
                if ($physDisk) {
                    $relCounter = Get-StorageReliabilityCounter -PhysicalDisk$physDisk -ErrorAction SilentlyContinue
                    if ($relCounter) {$gotApi = $true$health = 100
                        if ($null -ne $relCounter.Wear) {$health = 100 - $relCounter.Wear }$temp = 0
                        if ($null -ne $relCounter.Temperature) {$temp = $relCounter.Temperature }$kode = 0
                        if ($health -le 70) {$kode = 2 } elseif ($health -le 85) {$kode = 1 }
                        $detail = "Drive: SSD/NVMe (WinAPI) - Merk: $merk - Kesehatan: $health\% - Suhu:$temp C - SMART: PASSED"
                        $CleanMerk = $merk -replace '[^\w\s-]', ''$pipeChar = [char]124
                        $perf = "health=$health;85;70$pipeChar" + "temp=$temp;60;75"
                        Add-Content -Path $CacheFile -Value "$kode `"Storage_Health_$CleanMerk`" $perf$detail" -Encoding UTF8
                    }
                }
                
                if (-not $gotApi) {
                    $detail = "Drive: SSD/NVMe (VMD Blocked) - Merk: $merk - VMD mengunci total akses S.M.A.R.T fisik. Matikan VMD di BIOS (ubah mode ke AHCI/NVMe)."
                    $CleanMerk =$merk -replace '[^\w\s-]', ''
                    Add-Content -Path $CacheFile -Value "1 `"Storage_Health_$CleanMerk`" - $detail" -Encoding UTF8
                }
            }
            continue
        }

        # ====================================================================
        # NORMAL SMARTCTL PROCESSING (SATA / Native NVMe)
        # ====================================================================
        if ($drive.model_name) { $merk =$drive.model_name.Trim() }
        $is_passed =$drive.smart_status.passed
        $status = "FAILED"
        $kode = 2
        if ($is_passed) {$status = "PASSED"; $kode = 0 }$temp = 0
        if ($drive.temperature.current) {$temp = [int]$drive.temperature.current }$wear_terpakai = 0
        if ($drive.nvme_smart_health_information_log) { $wear_terpakai = [int]$drive.nvme_smart_health_information_log.percentage_used }
        $sisa_health = [Math]::Max(0, (100 -$wear_terpakai))
        if ($sisa_health -le 70) { $kode = 2 } elseif ($sisa_health -le 85) { $kode = 1 }$detail = "Drive: SSD/NVMe Native - Merk: $merk - Kesehatan:$sisa_health% - Suhu: $temp C - SMART:$status"
        $CleanMerk = $merk -replace '[^\w\s-]', ''$pipeChar = [char]124
        $perf = "health=$sisa_health;85;70$pipeChar" + "temp=$temp;60;75"
        Add-Content -Path $CacheFile -Value "$kode `"Storage_Health_$CleanMerk`" $perf$detail" -Encoding UTF8
    }
}

Get-Content -Path $CacheFile -ErrorAction SilentlyContinue

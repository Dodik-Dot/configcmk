# =====================================================================
# Local Check Checkmk: Daily Remote Apps Inventory Scan (Windows)
# Targeted Apps: AnyDesk, RustDesk, AnyViewer
# Scheduled to run once a day at 16:00
# =====================================================================
$ErrorActionPreference = 'SilentlyContinue'
$CacheDir  = "$env:ProgramData\checkmk\agent\cache"
if (-not (Test-Path $CacheDir)) { New-Item -ItemType Directory -Force$CacheDir | Out-Null }
$CacheFile = Join-Path$CacheDir "cache_remote_apps.txt"

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

    $RemoteList = [System.Collections.Generic.List[string]]::new()

    # =================================================================
    # 1. DETEKSI ANYDESK
    # =================================================================
    $AnyDeskID =$null
    
    # Cek System Service Config (Installed Version)
    $AnySysPaths = @(
        "$env:ProgramData\AnyDesk\system.conf",
        "${env:ProgramFiles(x86)}\AnyDesk\system.conf",
        "$env:ProgramFiles\AnyDesk\system.conf"
    )
    foreach ($p in$AnySysPaths) {
        if (Test-Path $p) {$c = Get-Content $p -ErrorAction SilentlyContinue$line = $c \vert{} Where-Object {$_ -match "^\s*ad\.id\s*=" } | Select-Object -First 1
            if ($line) {
                $AnyDeskID = ($line -replace "ad\.id\s*=", "").Trim()
                break
            }
        }
    }

    # Cek User Profiles jika dijalankan Portable / Standalone
    if (-not $AnyDeskID) {$UserAnyConf = Get-ChildItem -Path "C:\Users\*\AppData\Roaming\AnyDesk\system.conf" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($UserAnyConf) {$c = Get-Content $UserAnyConf.FullName -ErrorAction SilentlyContinue$line = $c \vert{} Where-Object {$_ -match "^\s*ad\.id\s*=" } | Select-Object -First 1
            if ($line) {
                $AnyDeskID = ($line -replace "ad\.id\s*=", "").Trim()
            }
        }
    }

    # Fallback Registry
    if (-not $AnyDeskID) {$AnyDeskID = Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\AnyDesk\Client" -Name "ad.id" -ErrorAction SilentlyContinue
        if (-not $AnyDeskID) {$AnyDeskID = Get-ItemPropertyValue -Path "HKCU:\Software\AnyDesk\Client" -Name "ad.id" -ErrorAction SilentlyContinue
        }
    }

    if ($AnyDeskID) {
        $RemoteList.Add("AnyDesk (ID: $AnyDeskID)")
    } elseif (Get-Process -Name "AnyDesk" -ErrorAction SilentlyContinue) {
        $RemoteList.Add("AnyDesk (Running)")
    }

    # =================================================================
    # 2. DETEKSI RUSTDESK
    # =================================================================
    $RustDeskID = $null$RustConfFiles = @(
        "$env:ProgramData\RustDesk\config\RustDesk2.toml",
        "$env:ProgramData\RustDesk\config\rustdesk.toml",
        "$env:APPDATA\RustDesk\config\RustDesk2.toml",
        "$env:APPDATA\RustDesk\config\rustdesk.toml"
    )
    $UserRust = Get-ChildItem -Path "C:\Users\*\AppData\Roaming\RustDesk\config\*.toml" -ErrorAction SilentlyContinue
    if ($UserRust) {
        foreach ($f in$UserRust) { $RustConfFiles +=$f.FullName }
    }

    foreach ($rcPath in$RustConfFiles) {
        if (Test-Path $rcPath) {$rContent = Get-Content $rcPath -ErrorAction SilentlyContinue$idLine = $rContent \vert{} Where-Object {$_ -match '^\s*id\s*=' } | Select-Object -First 1
            if ($idLine) {
                $RustDeskID = ($idLine -split '=' | Select-Object -Last 1).Trim().Trim('"').Trim("'").Trim()
                if ($RustDeskID) { break }
            }
        }
    }

    if ($RustDeskID) {
        $RemoteList.Add("RustDesk (ID: $RustDeskID)")
    } elseif (Get-Process -Name "rustdesk" -ErrorAction SilentlyContinue) {
        $RemoteList.Add("RustDesk (Running)")
    }

    # =================================================================
    # 3. DETEKSI ANYVIEWER
    # =================================================================
    $AnyViewerID =$null

    # Cek Registry AnyViewer (32-bit & 64-bit node)
    $AvRegPaths = @(
        "HKLM:\SOFTWARE\AOMEI\AnyViewer",
        "HKLM:\SOFTWARE\WOW6432Node\AOMEI\AnyViewer",
        "HKCU:\Software\AOMEI\AnyViewer"
    )
    foreach ($reg in$AvRegPaths) {
        if (Test-Path $reg) {
            $val = Get-ItemPropertyValue -Path$reg -Name "DeviceID" -ErrorAction SilentlyContinue
            if (-not $val) { $val = Get-ItemPropertyValue -Path$reg -Name "ClientID" -ErrorAction SilentlyContinue }
            if ($val) {
                $AnyViewerID = [string]$val
                break
            }
        }
    }

    # Cek File Konfigurasi AnyViewer jika Registry tidak memuat ID
    if (-not $AnyViewerID) {$AvConfFiles = @(
            "$env:ProgramData\AnyViewer\config.ini",
            "$env:ProgramData\AOMEI\AnyViewer\config.ini"
        )
        $UserAv = Get-ChildItem -Path "C:\Users\*\AppData\Roaming\AnyViewer\config.ini" -ErrorAction SilentlyContinue
        if ($UserAv) {
            foreach ($f in$UserAv) { $AvConfFiles +=$f.FullName }
        }

        foreach ($cfg in$AvConfFiles) {
            if (Test-Path $cfg) {$c = Get-Content $cfg -ErrorAction SilentlyContinue$idLine = $c \vert{} Where-Object {$_ -match "^\s*(DeviceID|ClientID|cid)\s*=" } | Select-Object -First 1
                if ($idLine) {
                    $AnyViewerID = ($idLine -split '=' | Select-Object -Last 1).Trim()
                    if ($AnyViewerID) { break }
                }
            }
        }
    }

    # Cek Path Eksekusi / Proses jika ID belum terbaca
    $AvExeInstalled = (Test-Path "${env:ProgramFiles(x86)}\AnyViewer\AnyViewer.exe") -or 
                      (Test-Path "$env:ProgramFiles\AnyViewer\AnyViewer.exe") -or 
                      (Get-Process -Name "AnyViewer*" -ErrorAction SilentlyContinue)

    if ($AnyViewerID) {
        $RemoteList.Add("AnyViewer (ID: $AnyViewerID)")
    } elseif ($AvExeInstalled) {$RemoteList.Add("AnyViewer (Installed)")
    }

    # =================================================================
    # 4. FORMAT OUTPUT CHECKMK
    # =================================================================
    if ($RemoteList.Count -gt 0) {
        $Details =$RemoteList -join " | "
    } else {
        $Details = "No remote apps detected."
    }

    $OutputLine = "0 `"Remote_Apps`" - Status : OK | $Details"
    $OutputLine \vert{} Out-File -FilePath$CacheFile -Encoding utf8 -Force
}

Get-Content $CacheFile -ErrorAction SilentlyContinue

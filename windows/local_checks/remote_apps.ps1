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
    $CacheSize  = (Get-Item$CacheFile).Length
    if ($CacheMtime -ge $Last16 -and$CacheSize -gt 10) {
        $NeedUpdate =$false
    }
}

if ($NeedUpdate) {
    if (Test-Path $CacheFile) { Remove-Item$CacheFile -Force }

    $RemoteList = @()

    # --- 1. ANYDESK ---
    $AnyDeskID = $null$AnySysPaths = @(
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

    if (-not $AnyDeskID) {$UserAnyConf = Get-ChildItem -Path "C:\Users\*\AppData\Roaming\AnyDesk\system.conf" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($UserAnyConf) {$c = Get-Content $UserAnyConf.FullName -ErrorAction SilentlyContinue$line = $c \vert{} Where-Object {$_ -match "^\s*ad\.id\s*=" } | Select-Object -First 1
            if ($line) {
                $AnyDeskID = ($line -replace "ad\.id\s*=", "").Trim()
            }
        }
    }

    if (-not $AnyDeskID) {$regVal = Get-ItemProperty -Path "HKLM:\SOFTWARE\AnyDesk\Client" -ErrorAction SilentlyContinue
        if ($regVal -and$regVal.'ad.id') { $AnyDeskID =$regVal.'ad.id' }
    }

    if ($AnyDeskID) {
        $RemoteList += "AnyDesk (ID: $AnyDeskID)"
    } elseif (Get-Process -Name "AnyDesk" -ErrorAction SilentlyContinue) {
        $RemoteList += "AnyDesk (Running)"
    }

    # --- 2. RUSTDESK ---
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
        $RemoteList += "RustDesk (ID: $RustDeskID)"
    } elseif (Get-Process -Name "rustdesk" -ErrorAction SilentlyContinue) {
        $RemoteList += "RustDesk (Running)"
    }

    # --- 3. ANYVIEWER ---
    $AnyViewerID = $null$AvRegPaths = @(
        "HKLM:\SOFTWARE\AOMEI\AnyViewer",
        "HKLM:\SOFTWARE\WOW6432Node\AOMEI\AnyViewer"
    )
    foreach ($reg in$AvRegPaths) {
        $val = Get-ItemProperty -Path$reg -ErrorAction SilentlyContinue
        if ($val) {
            if ($val.DeviceID) { $AnyViewerID = [string]$val.DeviceID; break }
            if ($val.ClientID) { $AnyViewerID = [string]$val.ClientID; break }
        }
    }

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

    $AvInstalled = (Test-Path "${env:ProgramFiles(x86)}\AnyViewer\AnyViewer.exe") -or 
                   (Test-Path "$env:ProgramFiles\AnyViewer\AnyViewer.exe") -or 
                   (Get-Process -Name "AnyViewer*" -ErrorAction SilentlyContinue)

    if ($AnyViewerID) {
        $RemoteList += "AnyViewer (ID: $AnyViewerID)"
    } elseif ($AvInstalled) {$RemoteList += "AnyViewer (Installed)"
    }

    # Format Output Checkmk
    if ($RemoteList.Count -gt 0) {
        $Details =$RemoteList -join " | "
    } else {
        $Details = "No remote apps detected."
    }

    $OutputLine = "0 `"Remote_Apps`" - Status : OK | $Details"
    $OutputLine \vert{} Out-File -FilePath$CacheFile -Encoding utf8 -Force
}

if (Test-Path $CacheFile) {
    Get-Content $CacheFile -ErrorAction SilentlyContinue
} else {
    Write-Output "0 `"Remote_Apps`" - Status : OK | No remote apps detected."
}

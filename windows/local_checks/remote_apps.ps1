# =====================================================================
# Local Check Checkmk: Daily Remote Apps Inventory Scan (Windows)
# Apps: AnyDesk, RustDesk, AnyViewer
# Scheduled to run once a day at 16:00
# =====================================================================
$ErrorActionPreference = 'SilentlyContinue'
$CacheDir = "$env:ProgramData\checkmk\agent\cache"
if (-not (Test-Path $CacheDir)) { New-Item -ItemType Directory -Force$CacheDir | Out-Null }
$CacheFile = Join-Path$CacheDir "cache_remote_apps.txt"

# Get current hour and today's 16:00 threshold
$Now = Get-Date$Today16 = Get-Date -Hour 16 -Minute 0 -Second 0
if ($Now -lt$Today16) {
    $Last16 =$Today16.AddDays(-1)
} else {
    $Last16 =$Today16
}

$NeedUpdate =$true
if (Test-Path $CacheFile) {
    $CacheMtime = (Get-Item$CacheFile).LastWriteTime
    $CacheSize  = (Get-Item$CacheFile).Length
    if ($CacheMtime -ge $Last16 -and$CacheSize -gt 15) {
        $NeedUpdate =$false
    }
}

if ($NeedUpdate) {
    if (Test-Path $CacheFile) { Remove-Item$CacheFile -Force }

    $users = Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue | Where-Object { 
        $_.Name -notmatch "^(Public\vert{}Default\vert{}Default User\vert{}All Users)$" 
    }

    $ANYDESK_ID   = ""
    $RUSTDESK_ID  = ""
    $ANYVIEWER_ID = ""

    # --- 1. DETEKSI ANYDESK ---
    $ad_paths = @("$env:ProgramData\AnyDesk\system.conf")
    if ($users) {
        foreach ($u in $users) {$ad_paths += "$($u.FullName)\AppData\Roaming\AnyDesk\system.conf" 
        }
    }
    foreach ($p in$ad_paths) {
        if (Test-Path $p) {
            $ad_conf = Get-Content$p -ErrorAction SilentlyContinue
            $ad_line =$ad_conf | Where-Object { $_ -match "^ad\.anynet\.id=" -or $_ -match "^ad\.id=" } | Select-Object -First 1
            if ($ad_line) { 
                $ANYDESK_ID = ($ad_line -split "=")[1].Trim()
                break 
            }
        }
    }

    # --- 2. DETEKSI RUSTDESK ---
    $rd_exe = @(
        "$env:ProgramFiles\RustDesk\rustdesk.exe", 
        "${env:ProgramFiles(x86)}\RustDesk\rustdesk.exe", 
        "$env:LOCALAPPDATA\Programs\RustDesk\rustdesk.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1

    if ($rd_exe) {$cli_out = (& $rd_exe --get-id 2>$null | Out-String).Trim()
        if ($cli_out -match '^\d{8,15}$') { 
            $RUSTDESK_ID =$cli_out 
        }
    }

    if (-not $RUSTDESK_ID) {$rd_paths = @(
            "$env:ProgramData\RustDesk\config\RustDesk2.toml", 
            "$env:ProgramData\RustDesk\config\rustdesk.toml"
        )
        if ($users) {
            foreach ($u in $users) {$rd_paths += "$($u.FullName)\AppData\Roaming\RustDesk\config\RustDesk2.toml"
                $rd_paths += "$($u.FullName)\AppData\Roaming\RustDesk\config\rustdesk.toml"
            }
        }
        foreach ($p in$rd_paths) {
            if (Test-Path $p) {
                $content = Get-Content$p -Raw -ErrorAction SilentlyContinue
                if ($content -match '(?m)^\s*id\s*=\s*[''"]?(\d{8,15})[''"]?') { 
                    $RUSTDESK_ID =$matches[1].Trim()
                    break 
                }
            }
        }
    }

    # --- 3. DETEKSI ANYVIEWER ---
    $hu = Get-ChildItem -Path "Registry::HKEY_USERS" -ErrorAction SilentlyContinue
    if ($hu) {
        foreach ($h in$hu) {
            if ($h.PSChildName -notmatch "_Classes$") {
                $av_reg = "$($h.PSPath)\SOFTWARE\Aomei\AnyViewer\Option"
                if (Test-Path $av_reg) {
                    $val = Get-ItemPropertyValue -Path$av_reg -Name "DeviceID" -ErrorAction SilentlyContinue
                    if ($val) { 
                        $ANYVIEWER_ID = [string]$val
                        break 
                    }
                }
            }
        }
    }

    if (-not $ANYVIEWER_ID) {$val = Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\WOW6432Node\Aomei\AnyViewer\Option" -Name "DeviceID" -ErrorAction SilentlyContinue
        if ($val) { $ANYVIEWER_ID = [string]$val }
    }

    if (-not $ANYVIEWER_ID) {$av_files = @(
            "$env:ProgramData\AnyViewer\config.ini", 
            "$env:ProgramFiles\AnyViewer\config.ini", 
            "${env:ProgramFiles(x86)}\AnyViewer\config.ini"
        )
        if ($users) {
            foreach ($u in $users) {$av_files += "$($u.FullName)\AppData\Roaming\AnyViewer\config.ini" 
                $av_files += "$($u.FullName)\AppData\Local\AnyViewer\config.ini"
            }
        }
        foreach ($f in$av_files) {
            if (Test-Path $f) {
                $txt = Get-Content$f -Raw -ErrorAction SilentlyContinue
                if ($txt -match '(?mi)^\s*(?:DeviceId|cid|ClientID)\s*=\s*([^\r\n]+)') {
                    $ANYVIEWER_ID =$matches[1].Trim()
                    break
                }
            }
        }
    }

    if (-not $ANYVIEWER_ID) {
        if ((Test-Path "$env:ProgramFiles\AnyViewer\AnyViewer.exe") -or (Test-Path "${env:ProgramFiles(x86)}\AnyViewer\AnyViewer.exe") -or (Get-Process -Name "AnyViewer*" -ErrorAction SilentlyContinue)) {
            $ANYVIEWER_ID = "Installed"
        }
    }

    # --- FORMAT DETAIL OUTPUT ---
    $RemoteList = @()
    if ($ANYDESK_ID)   { $RemoteList += "AnyDesk: $ANYDESK_ID" }
    if ($RUSTDESK_ID)  { $RemoteList += "RustDesk: $RUSTDESK_ID" }
    if ($ANYVIEWER_ID) { $RemoteList += "AnyViewer: $ANYVIEWER_ID" }

    if ($RemoteList.Count -gt 0) {
        $Details =$RemoteList -join " | "
    } else {
        $Details = "No remote apps detected."
    }

    $Output = "0 `"Remote_Apps`" - Status : OK | $Details"
    $Output \vert{} Out-File -FilePath$CacheFile -Encoding utf8 -Force
}

Get-Content $CacheFile -ErrorAction SilentlyContinue

# =====================================================================
# Local Check Checkmk: Remote Apps Inventory Scan (Windows)
# Targets: AnyDesk, RustDesk, AnyViewer
# Engine: Direct Standard Output + Daily/Weekly Auto Cache
# =====================================================================
$ErrorActionPreference = 'SilentlyContinue'
$CacheDir = "$env:ProgramData\checkmk\agent\cache"
if (-not (Test-Path $CacheDir)) { New-Item -ItemType Directory -Force$CacheDir | Out-Null }
$CacheFile = Join-Path$CacheDir "cache_remote_apps.txt"

# Jadwal Cache Harian Pukul 16:00
$Now = Get-Date
$Today16 = Get-Date -Hour 16 -Minute 0 -Second 0$Last16  = if ($Now -lt$Today16) { $Today16.AddDays(-1) } else {$Today16 }

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

    $ANYDESK_ID   = "Not Installed"
    $RUSTDESK_ID  = "Not Installed"
    $ANYVIEWER_ID = "Not Installed"

    # 1. ANYDESK
    $ad_paths = @("$env:ProgramData\AnyDesk\system.conf")
    foreach ($u in $users) {$ad_paths += "$($u.FullName)\AppData\Roaming\AnyDesk\system.conf" }
    foreach ($path in$ad_paths) {
        if (Test-Path $path) {
            $ad_conf = Get-Content$path -ErrorAction SilentlyContinue
            $ad_line =$ad_conf | Where-Object { $_ -match "^ad\.anynet\.id=" -or $_ -match "^ad\.id=" } | Select-Object -First 1
            if ($ad_line) {
                $ANYDESK_ID = ($ad_line -split "=")[1].Trim()
                break
            }
        }
    }

    # 2. RUSTDESK
    $rd_exe = @(
        "$env:ProgramFiles\RustDesk\rustdesk.exe", 
        "${env:ProgramFiles(x86)}\RustDesk\rustdesk.exe", 
        "$env:LOCALAPPDATA\Programs\RustDesk\rustdesk.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1

    if ($rd_exe) {$cli_out = (& $rd_exe --get-id 2>$null | Out-String).Trim()
        if ($cli_out -match '^\d{8,15}$') { $RUSTDESK_ID =$cli_out }
    }

    if ($RUSTDESK_ID -eq "Not Installed") {
        $rd_paths = @("$env:ProgramData\RustDesk\config\RustDesk2.toml", "$env:ProgramData\RustDesk\config\RustDesk.toml")
        foreach ($u in $users) {$rd_paths += "$($u.FullName)\AppData\Roaming\RustDesk\config\RustDesk2.toml"
            $rd_paths += "$($u.FullName)\AppData\Roaming\RustDesk\config\rustdesk.toml"
        }
        foreach ($path in$rd_paths) {
            if (Test-Path $path) {
                $content = Get-Content$path -Raw -ErrorAction SilentlyContinue
                if ($content -match '(?m)^\s*id\s*=\s*[''"]?(\d{8,15})[''"]?') {
                    $RUSTDESK_ID =$matches[1].Trim()
                    break
                }
            }
        }
    }

    # 3. ANYVIEWER
    $hu = Get-ChildItem -Path "Registry::HKEY_USERS" -ErrorAction SilentlyContinue
    foreach ($h in$hu) {
        if ($h.PSChildName -notmatch "_Classes$") {
            $av_reg = "$($h.PSPath)\SOFTWARE\Aomei\AnyViewer\Option"
            if (Test-Path $av_reg) {
                $val = Get-ItemPropertyValue -Path$av_reg -Name "DeviceID" -ErrorAction SilentlyContinue
                if (-not $val) { $val = Get-ItemPropertyValue -Path$av_reg -Name "ClientID" -ErrorAction SilentlyContinue }
                if ($val) { $ANYVIEWER_ID = [string]$val; break }
            }
        }
    }
    if ($ANYVIEWER_ID -eq "Not Installed") {
        $val = Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\WOW6432Node\Aomei\AnyViewer\Option" -Name "DeviceID" -ErrorAction SilentlyContinue
        if ($val) { $ANYVIEWER_ID = [string]$val }
    }
    if ($ANYVIEWER_ID -eq "Not Installed") {
        $av_files = @("$env:ProgramData\AnyViewer\config.ini", "$env:ProgramFiles\AnyViewer\config.ini", "${env:ProgramFiles(x86)}\AnyViewer\config.ini")
        foreach ($u in $users) {$av_files += "$($u.FullName)\AppData\Roaming\AnyViewer\config.ini"
            $av_files += "$($u.FullName)\AppData\Local\AnyViewer\config.ini"
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
    if ($ANYVIEWER_ID -eq "Not Installed") {
        if ((Test-Path "$env:ProgramFiles\AnyViewer\AnyViewer.exe") -or (Test-Path "${env:ProgramFiles(x86)}\AnyViewer\AnyViewer.exe") -or (Get-Process -Name "AnyViewer*" -ErrorAction SilentlyContinue)) {
            $ANYVIEWER_ID = "Installed"
        }
    }

    # Format Output Resmi Checkmk Local Check
    $Detail = "OK: AnyDesk: $ANYDESK_ID | RustDesk: $RUSTDESK_ID \vert{} AnyViewer:$ANYVIEWER_ID"
    $OutputLine = "0 `"Remote_Apps`" - $Detail"
    
    [System.IO.File]::WriteAllLines($CacheFile, @($OutputLine), [System.Text.Encoding]::UTF8)
}

# Standard Output Pipeline (Wajib agar terbaca agen Checkmk)
if (Test-Path $CacheFile) {
    Get-Content $CacheFile
} else {
    Write-Output "0 `"Remote_Apps`" - OK: AnyDesk: Not Installed | RustDesk: Not Installed | AnyViewer: Not Installed"
}

# =====================================================================
# Checkmk Local Check: Remote Apps Inventory (Windows)
# Targets: AnyDesk, RustDesk, AnyViewer
# Service Name: Remote_Apps
# =====================================================================
$ErrorActionPreference = 'SilentlyContinue'

$users = Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue | Where-Object { 
    $_.Name -notmatch "^(Public\vert{}Default\vert{}Default User\vert{}All Users)$" 
}

$ANYDESK_ID   = "Not Installed"
$RUSTDESK_ID  = "Not Installed"
$ANYVIEWER_ID = "Not Installed"

# 1. AnyDesk (Logika asli cek_remote yang terbukti membaca ID)
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

# 2. RustDesk (Logika CLI & Config TOML)
$rd_exe = @(
    "$env:ProgramFiles\RustDesk\rustdesk.exe", 
    "${env:ProgramFiles(x86)}\RustDesk\rustdesk.exe", 
    "$env:LOCALAPPDATA\Programs\RustDesk\rustdesk.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($rd_exe) {$cli_out = (& $rd_exe --get-id 2>$null | Out-String).Trim()
    if ($cli_out -match '^\d{8,15}$') { $RUSTDESK_ID =$cli_out } 
}

if ($RUSTDESK_ID -eq "Not Installed") {
    $rd_paths = @(
        "$env:ProgramData\RustDesk\config\RustDesk2.toml", 
        "$env:ProgramData\RustDesk\config\RustDesk.toml",
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

# 3. AnyViewer (Membaca Registry Profil Pengguna, HKLM, dan Config INI)
$hu = Get-ChildItem -Path "Registry::HKEY_USERS" -ErrorAction SilentlyContinue
if ($hu) {
    foreach ($h in$hu) { 
        if ($h.PSChildName -notmatch "_Classes$") {
            $av_reg = "$($h.PSPath)\SOFTWARE\Aomei\AnyViewer\Option"
            if (Test-Path $av_reg) { 
                $val = Get-ItemPropertyValue -Path$av_reg -Name "DeviceID" -ErrorAction SilentlyContinue
                if (-not $val) { $val = Get-ItemPropertyValue -Path$av_reg -Name "ClientID" -ErrorAction SilentlyContinue }
                if ($val -and "$val" -match '\d{6,15}') { 
                    $ANYVIEWER_ID = "$val".Trim()
                    break 
                } 
            }
        }
    }
}

if ($ANYVIEWER_ID -eq "Not Installed") { 
    $val = Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\WOW6432Node\Aomei\AnyViewer\Option" -Name "DeviceID" -ErrorAction SilentlyContinue
    if (-not $val) {$val = Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\Aomei\AnyViewer\Option" -Name "DeviceID" -ErrorAction SilentlyContinue }
    if ($val) { $ANYVIEWER_ID = [string]$val } 
}

if ($ANYVIEWER_ID -eq "Not Installed") {
    $av_files = @(
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
            $c = Get-Content$f -Raw -ErrorAction SilentlyContinue
            if ($c -match '(?mi)^\s*(?:DeviceId|cid|ClientID)\s*=\s*([^\r\n]+)') {
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

# Output Wajib Menggunakan Write-Output agar terbaca agen Checkmk
Write-Output "0 `"Remote_Apps`" - OK: AnyDesk: $ANYDESK_ID | RustDesk: $RUSTDESK_ID \vert{} AnyViewer:$ANYVIEWER_ID"

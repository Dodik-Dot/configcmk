$ErrorActionPreference = 'SilentlyContinue'

$users = Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue | Where-Object { 
    $_.Name -notmatch "^(Public\vert{}Default\vert{}Default User\vert{}All Users)$" 
}

$ANYDESK_ID   = "Not Installed"
$RUSTDESK_ID  = "Not Installed"
$ANYVIEWER_ID = "Not Installed"

# 1. AnyDesk
$ad_paths = @("C:\ProgramData\AnyDesk\system.conf")
if ($users) {
    for ($i = 0; $i -lt$users.Count; $i++) {$ad_paths += ($users[$i].FullName + "\AppData\Roaming\AnyDesk\system.conf")
    }
}
for ($i = 0; $i -lt$ad_paths.Count; $i++) {$p = $ad_paths[$i]
    if (Test-Path $p) {
        $ad_conf = Get-Content -Path$p -ErrorAction SilentlyContinue
        $ad_line =$ad_conf | Where-Object { $_ -match "^ad\.anynet\.id=" -or $_ -match "^ad\.id=" } | Select-Object -First 1
        if ($ad_line) {
            $ANYDESK_ID = ($ad_line -split "=")[1].Trim()
            break
        }
    }
}

# 2. RustDesk
$rd_exe = @(
    "C:\Program Files\RustDesk\rustdesk.exe", 
    "C:\Program Files (x86)\RustDesk\rustdesk.exe", 
    "$env:LOCALAPPDATA\Programs\RustDesk\rustdesk.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($rd_exe) {$cli_out = (& $rd_exe --get-id 2>$null | Out-String).Trim()
    if ($cli_out -match '^\d{8,15}$') { 
        $RUSTDESK_ID =$cli_out 
    }
}

if ($RUSTDESK_ID -eq "Not Installed") {
    $rd_paths = @(
        "C:\ProgramData\RustDesk\config\RustDesk2.toml", 
        "C:\ProgramData\RustDesk\config\RustDesk.toml",
        "C:\ProgramData\RustDesk\config\rustdesk.toml"
    )
    if ($users) {
        for ($i = 0; $i -lt$users.Count; $i++) {$rd_paths += ($users[$i].FullName + "\AppData\Roaming\RustDesk\config\RustDesk2.toml")
            $rd_paths += ($users[$i].FullName + "\AppData\Roaming\RustDesk\config\rustdesk.toml")
        }
    }
    for ($i = 0; $i -lt$rd_paths.Count; $i++) {$p = $rd_paths[$i]
        if (Test-Path $p) {
            $content = Get-Content -Path$p -Raw -ErrorAction SilentlyContinue
            if ($content -match '(?m)^\s*id\s*=\s*[''"]?(\d{8,15})[''"]?') { 
                $RUSTDESK_ID =$matches[1].Trim()
                break 
            }
        }
    }
}

# 3. AnyViewer
$hu = Get-ChildItem -Path "Registry::HKEY_USERS" -ErrorAction SilentlyContinue
if ($hu) {
    for ($i = 0; $i -lt$hu.Count; $i++) {$h = $hu[$i]
        if ($h.PSChildName -notmatch "_Classes$") {
            $regKeys = @(
                ($h.PSPath + "\SOFTWARE\Aomei\AnyViewer\Option"),
                ($h.PSPath + "\SOFTWARE\Aomei\AnyViewer")
            )
            for ($j = 0; $j -lt$regKeys.Count; $j++) {$rk = $regKeys[$j]
                if (Test-Path $rk) {
                    $prop = Get-ItemProperty -Path$rk -ErrorAction SilentlyContinue
                    $val =$prop.DeviceID
                    if (-not $val) { $val =$prop.ClientID }
                    if (-not $val) { $val =$prop.cid }
                    if ($val -and "$val" -match '\d{6,15}') { 
                        $ANYVIEWER_ID = "$val".Trim()
                        break 
                    }
                }
            }
        }
        if ($ANYVIEWER_ID -ne "Not Installed") { break }
    }
}

if ($ANYVIEWER_ID -eq "Not Installed") {
    $hklmKeys = @(
        "HKLM:\SOFTWARE\WOW6432Node\Aomei\AnyViewer\Option",
        "HKLM:\SOFTWARE\Aomei\AnyViewer\Option",
        "HKLM:\SOFTWARE\WOW6432Node\Aomei\AnyViewer",
        "HKLM:\SOFTWARE\Aomei\AnyViewer"
    )
    for ($i = 0; $i -lt$hklmKeys.Count; $i++) {$hk = $hklmKeys[$i]
        if (Test-Path $hk) {
            $prop = Get-ItemProperty -Path$hk -ErrorAction SilentlyContinue
            $val =$prop.DeviceID
            if (-not $val) { $val =$prop.ClientID }
            if ($val -and "$val" -match '\d{6,15}') { 
                $ANYVIEWER_ID = "$val".Trim()
                break 
            }
        }
    }
}

if ($ANYVIEWER_ID -eq "Not Installed") {
    $av_files = @(
        "C:\ProgramData\AnyViewer\config.ini",
        "C:\Program Files\AnyViewer\config.ini",
        "C:\Program Files (x86)\AnyViewer\config.ini"
    )
    if ($users) {
        for ($i = 0; $i -lt$users.Count; $i++) {$av_files += ($users[$i].FullName + "\AppData\Roaming\AnyViewer\config.ini")
            $av_files += ($users[$i].FullName + "\AppData\Roaming\Aomei\AnyViewer\config.ini")
            $av_files += ($users[$i].FullName + "\AppData\Local\AnyViewer\config.ini")
            $av_files += ($users[$i].FullName + "\AppData\Roaming\AnyViewer\user.cfg")
        }
    }
    for ($i = 0; $i -lt$av_files.Count; $i++) {$f = $av_files[$i]
        if (Test-Path $f) {
            $c = Get-Content -Path$f -Raw -ErrorAction SilentlyContinue
            if ($c -match '(?mi)^\s*(?:DeviceId|cid|ClientID|account_id)\s*=\s*[''"]?(\d{6,15})') {
                $ANYVIEWER_ID =$matches[1].Trim()
                break
            }
        }
    }
}

if ($ANYVIEWER_ID -eq "Not Installed") {
    if ((Test-Path "C:\Program Files\AnyViewer\AnyViewer.exe") -or (Test-Path "C:\Program Files (x86)\AnyViewer\AnyViewer.exe") -or (Get-Process -Name "AnyViewer*" -ErrorAction SilentlyContinue)) {
        $ANYVIEWER_ID = "Installed"
    }
}

Write-Output "0 `"Remote_Apps`" - OK: AnyDesk: $ANYDESK_ID | RustDesk: $RUSTDESK_ID \vert{} AnyViewer:$ANYVIEWER_ID"

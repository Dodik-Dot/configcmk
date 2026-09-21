$ErrorActionPreference = 'SilentlyContinue'
$CacheFolder = "$env:ProgramData\checkmk\agent"
if (-not (Test-Path $CacheFolder)) { New-Item -ItemType Directory -Path$CacheFolder -Force | Out-Null }
$WeeklyCache = "$CacheFolder\cache_remote_apps.txt"

function Save-CacheAndOutput ([string]$FilePath, [System.Collections.Generic.List[string]]$Lines) {$CleanLines = [System.Collections.Generic.List[string]]::new()
    foreach ($l in$Lines) { 
        if (-not [string]::IsNullOrWhiteSpace($l)) { 
            $CleanLines.Add(($l -replace "[\r\n]+", " ").Trim()) 
        } 
    }
    if ($CleanLines.Count -gt 0) { 
        [System.IO.File]::WriteAllLines($FilePath,$CleanLines, [System.Text.Encoding]::UTF8)
        foreach ($cl in $CleanLines) { Write-Output$cl } 
    }
}

function Read-CacheAndOutput ([string]$FilePath) {
    if (Test-Path $FilePath) { 
        foreach ($l in [System.IO.File]::ReadAllLines($FilePath, [System.Text.Encoding]::UTF8)) { 
            if (-not [string]::IsNullOrWhiteSpace($l)) { Write-Output$l } 
        } 
    }
}

$Today = Get-Date$DaysSinceMonday = ([int]$Today.DayOfWeek - [int][DayOfWeek]::Monday + 7) \% 7$ThisMonday = $Today.Date.AddDays(-$DaysSinceMonday)

$NeedUpdateWeekly =$true
if (Test-Path $WeeklyCache) { 
    if ((Get-Item $WeeklyCache).LastWriteTime -ge $ThisMonday -and (Get-Item$WeeklyCache).Length -gt 15) { 
        $NeedUpdateWeekly =$false 
    } 
}

if ($NeedUpdateWeekly) {$linesWeekly = [System.Collections.Generic.List[string]]::new()
    try {
        $users = Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue | Where-Object { 
            $_.Name -notmatch "^(Public\vert{}Default\vert{}Default User\vert{}All Users)$" 
        }
        $ANYDESK_ID   = "Not Installed"
        $RUSTDESK_ID  = "Not Installed"
        $ANYVIEWER_ID = "Not Installed"

        # 1. AnyDesk (Logika Asli Anda)
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

        # 2. RustDesk (Logika Asli Anda)
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

        # 3. AnyViewer (Pencarian Menyeluruh)
        # Registry HKU
        $hu = Get-ChildItem -Path "Registry::HKEY_USERS" -ErrorAction SilentlyContinue
        foreach ($h in$hu) { 
            if ($h.PSChildName -notmatch "_Classes$") {
                $regKeys = @(
                    "$($h.PSPath)\SOFTWARE\Aomei\AnyViewer\Option",
                    "$($h.PSPath)\SOFTWARE\Aomei\AnyViewer"
                )
                foreach ($rk in$regKeys) {
                    if (Test-Path $rk) {
                        $prop = Get-ItemProperty -Path$rk -ErrorAction SilentlyContinue
                        $val =$prop.DeviceID; if (-not $val) {$val = $prop.ClientID }; if (-not$val) { $val =$prop.cid }
                        if ($val -and "$val" -match '\d{6,15}') { $ANYVIEWER_ID = "$val".Trim(); break }
                    }
                }
            }
            if ($ANYVIEWER_ID -ne "Not Installed") { break }
        }

        # Registry HKLM
        if ($ANYVIEWER_ID -eq "Not Installed") { 
            $hklmKeys = @(
                "HKLM:\SOFTWARE\WOW6432Node\Aomei\AnyViewer\Option",
                "HKLM:\SOFTWARE\Aomei\AnyViewer\Option",
                "HKLM:\SOFTWARE\WOW6432Node\Aomei\AnyViewer",
                "HKLM:\SOFTWARE\Aomei\AnyViewer"
            )
            foreach ($hk in$hklmKeys) {
                if (Test-Path $hk) {$prop = Get-ItemProperty -Path $hk -ErrorAction SilentlyContinue$val = $prop.DeviceID; if (-not$prop.DeviceID) { $val =$prop.ClientID }
                    if ($val -and "$val" -match '\d{6,15}') { $ANYVIEWER_ID = "$val".Trim(); break }
                }
            }
        }

        # File config.ini / user.cfg
        if ($ANYVIEWER_ID -eq "Not Installed") {
            $av_files = @(
                "$env:ProgramData\AnyViewer\config.ini",
                "$env:ProgramFiles\AnyViewer\config.ini",
                "${env:ProgramFiles(x86)}\AnyViewer\config.ini"
            )
            foreach ($u in $users) {$av_files += "$($u.FullName)\AppData\Roaming\AnyViewer\config.ini"
                $av_files += "$($u.FullName)\AppData\Roaming\Aomei\AnyViewer\config.ini"
                $av_files += "$($u.FullName)\AppData\Local\AnyViewer\config.ini"
                $av_files += "$($u.FullName)\AppData\Roaming\AnyViewer\user.cfg"
            }
            foreach ($f in$av_files) {
                if (Test-Path $f) {
                    $c = Get-Content$f -Raw -ErrorAction SilentlyContinue
                    if ($c -match '(?mi)^\s*(?:DeviceId|cid|ClientID|account_id)\s*=\s*[''"]?(\d{6,15})') {
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

        # Output menggunakan nama Remote_Apps agar cocok dengan Checkmk
        $linesWeekly.Add("0 `"Remote_Apps`" - OK: AnyDesk: $ANYDESK_ID | RustDesk: $RUSTDESK_ID \vert{} AnyViewer:$ANYVIEWER_ID")
    } catch {}

    Save-CacheAndOutput -FilePath $WeeklyCache -Lines$linesWeekly
} else { 
    Read-CacheAndOutput -FilePath $WeeklyCache 
}

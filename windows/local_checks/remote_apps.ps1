# =====================================================================
# Checkmk Local Check: Remote Apps Inventory (Windows)
# Supports: AnyDesk, RustDesk, AnyViewer
# Cache Interval: Weekly (Runs every Monday at 10:00 / on-demand)
# =====================================================================
$ErrorActionPreference = 'SilentlyContinue'
$CacheFolder = "$env:ProgramData\checkmk\agent"
if (-not (Test-Path $CacheFolder)) {
    New-Item -ItemType Directory -Path $CacheFolder -Force | Out-Null
}
$WeeklyCache = Join-Path$CacheFolder "cache_remote_apps.txt"

function Save-CacheAndOutput ([string]$FilePath, [System.Collections.Generic.List[string]]$Lines) {$CleanLines = [System.Collections.Generic.List[string]]::new()
    foreach ($l in$Lines) {
        if (-not [string]::IsNullOrWhiteSpace($l)) {
            $clean = ($l -replace "[\r\n]+", " ").Trim()
            $CleanLines.Add($clean)
        }
    }
    if ($CleanLines.Count -gt 0) {
        [System.IO.File]::WriteAllLines($FilePath,$CleanLines, [System.Text.Encoding]::UTF8)
        foreach ($cl in $CleanLines) { Write-Host$cl }
    }
}

function Read-CacheAndOutput ([string]$FilePath) {
    if (Test-Path $FilePath) {
        $lines = [System.IO.File]::ReadAllLines($FilePath, [System.Text.Encoding]::UTF8)
        foreach ($l in$lines) {
            if (-not [string]::IsNullOrWhiteSpace($l)) { Write-Host$l }
        }
    }
}

# Perhitungan jadwal mingguan (Setiap Senin)
$Today = Get-Date$DaysSinceMonday = ([int]$Today.DayOfWeek - [int][DayOfWeek]::Monday + 7) \% 7$ThisMonday = $Today.Date.AddDays(-$DaysSinceMonday)

$NeedUpdateWeekly =$true
if (Test-Path $WeeklyCache) {
    $CacheTime = (Get-Item$WeeklyCache).LastWriteTime
    $CacheSize = (Get-Item$WeeklyCache).Length
    if ($CacheTime -ge $ThisMonday -and$CacheSize -gt 10) {
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

        # -------------------------------------------------------------
        # 1. DETEKSI ANYDESK (System Service, User Profiles, Registry)
        # -------------------------------------------------------------
        $ad_paths = @(
            "$env:ProgramData\AnyDesk\system.conf",
            "$env:ProgramFiles\AnyDesk\system.conf",
            "${env:ProgramFiles(x86)}\AnyDesk\system.conf"
        )
        foreach ($u in $users) {$ad_paths += "$($u.FullName)\AppData\Roaming\AnyDesk\system.conf"
        }

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

        # Fallback Registry AnyDesk
        if ($ANYDESK_ID -eq "Not Installed") {
            $regAd = Get-ItemProperty "HKLM:\SOFTWARE\AnyDesk\Client" -ErrorAction SilentlyContinue
            if ($regAd -and$regAd.'ad.id') {
                $ANYDESK_ID = [string]$regAd.'ad.id'
            }
        }

        # -------------------------------------------------------------
        # 2. DETEKSI RUSTDESK (CLI --get-id, Config TOML, User AppData)
        # -------------------------------------------------------------
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

        if ($RUSTDESK_ID -eq "Not Installed") {
            $rd_paths = @(
                "$env:ProgramData\RustDesk\config\RustDesk2.toml",
                "$env:ProgramData\RustDesk\config\RustDesk.toml"
            )
            foreach ($u in $users) {$rd_paths += "$($u.FullName)\AppData\Roaming\RustDesk\config\RustDesk2.toml"
                $rd_paths += "$($u.FullName)\AppData\Roaming\RustDesk\config\RustDesk.toml"
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

        # -------------------------------------------------------------
        # 3. DETEKSI ANYVIEWER (Registry HKU/HKLM, Config INI, Executable)
        # -------------------------------------------------------------
        # Tahap A: Registry HKU (User Profile aktif)
        $hu = Get-ChildItem -Path "Registry::HKEY_USERS" -ErrorAction SilentlyContinue
        foreach ($h in$hu) {
            if ($h.PSChildName -notmatch "_Classes$") {
                $regPaths = @(
                    "$($h.PSPath)\SOFTWARE\Aomei\AnyViewer\Option",
                    "$($h.PSPath)\SOFTWARE\Aomei\AnyViewer"
                )
                foreach ($rp in$regPaths) {
                    if (Test-Path $rp) {
                        $val = Get-ItemPropertyValue -Path$rp -Name "DeviceID" -ErrorAction SilentlyContinue
                        if (-not $val) { $val = Get-ItemPropertyValue -Path$rp -Name "ClientID" -ErrorAction SilentlyContinue }
                        if ($val -and "$val" -match '\d{6,15}') {
                            $ANYVIEWER_ID = "$val".Trim()
                            break
                        }
                    }
                }
            }
            if ($ANYVIEWER_ID -ne "Not Installed") { break }
        }

        # Tahap B: Registry Mesin (HKLM)
        if ($ANYVIEWER_ID -eq "Not Installed") {
            $hklmPaths = @(
                "HKLM:\SOFTWARE\WOW6432Node\Aomei\AnyViewer\Option",
                "HKLM:\SOFTWARE\Aomei\AnyViewer\Option",
                "HKLM:\SOFTWARE\WOW6432Node\Aomei\AnyViewer",
                "HKLM:\SOFTWARE\Aomei\AnyViewer"
            )
            foreach ($hp in$hklmPaths) {
                if (Test-Path $hp) {
                    $val = Get-ItemPropertyValue -Path$hp -Name "DeviceID" -ErrorAction SilentlyContinue
                    if (-not $val) { $val = Get-ItemPropertyValue -Path$hp -Name "ClientID" -ErrorAction SilentlyContinue }
                    if ($val -and "$val" -match '\d{6,15}') {
                        $ANYVIEWER_ID = "$val".Trim()
                        break
                    }
                }
            }
        }

        # Tahap C: File Konfigurasi (ProgramData & AppData)
        if ($ANYVIEWER_ID -eq "Not Installed") {
            $av_files = @(
                "$env:ProgramData\AnyViewer\config.ini",
                "$env:ProgramData\Aomei\AnyViewer\config.ini",
                "$env:ProgramFiles\AnyViewer\config.ini",
                "${env:ProgramFiles(x86)}\AnyViewer\config.ini"
            )
            foreach ($u in $users) {$av_files += "$($u.FullName)\AppData\Roaming\AnyViewer\config.ini"
                $av_files += "$($u.FullName)\AppData\Roaming\Aomei\AnyViewer\config.ini"
                $av_files += "$($u.FullName)\AppData\Local\AnyViewer\config.ini"
            }
            foreach ($f in$av_files) {
                if (Test-Path $f) {
                    $c = Get-Content$f -Raw -ErrorAction SilentlyContinue
                    if ($c -match '(?mi)^\s*(?:DeviceId|cid|ClientID)\s*=\s*[''"]?(\d{6,15})') {
                        $ANYVIEWER_ID =$matches[1].Trim()
                        break
                    }
                }
            }
        }

        # Tahap D: Fallback jika terpasang tapi ID belum terbuka
        if ($ANYVIEWER_ID -eq "Not Installed") {
            $isAvRun = Get-Process -Name "AnyViewer*" -ErrorAction SilentlyContinue
            $isAvInstalled = (Test-Path "$env:ProgramFiles\AnyViewer\AnyViewer.exe") -or 
                             (Test-Path "${env:ProgramFiles(x86)}\AnyViewer\AnyViewer.exe")
            if ($isAvRun -or $isAvInstalled) {$ANYVIEWER_ID = "Installed"
            }
        }

        # -------------------------------------------------------------
        # OUTPUT CHECKMK SERVICE
        # -------------------------------------------------------------
        $linesWeekly.Add("0 `"Remote_Apps`" - OK: AnyDesk: $ANYDESK_ID | RustDesk: $RUSTDESK_ID \vert{} AnyViewer:$ANYVIEWER_ID")
    } catch {
        $linesWeekly.Add("0 `"Remote_Apps`" - OK: AnyDesk: Not Installed | RustDesk: Not Installed | AnyViewer: Not Installed")
    }

    Save-CacheAndOutput -FilePath $WeeklyCache -Lines$linesWeekly
} else {
    Read-CacheAndOutput -FilePath $WeeklyCache
}

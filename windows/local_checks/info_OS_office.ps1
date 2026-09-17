# =====================================================================
# 4. MINGGUAN CHECK (Hanya Scan Baru Setiap Hari Senin)
# - Windows OS Info (Info_Windows)
# - Office Info (Info_Office: MS Office + LibreOffice + WPS)
# - RAM Hardware Info (RAM_Hardware_Info: Per Slot Detail)
# - Remote Access ID (Remote_Access_ID)
# =====================================================================
if ($NeedUpdateWeekly) {
    $linesWeekly = [System.Collections.Generic.List[string]]::new()

    # A. WINDOWS INVENTORY
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        $WinName = $os.Caption
        $WinArch = $os.OSArchitecture
        $WinBuild = $os.BuildNumber

        $WinVersion = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue).DisplayVersion
        $WinVersionName = switch ($WinVersion) {
            "25H2" { "Windows 11 2025 (25H2)" }
            "25H1" { "Windows 11 2025 (25H1)" }
            "24H2" { "Windows 11 2024 (24H2)" }
            "23H2" { "Windows 11 2023 (23H2)" }
            "22H2" { "Windows 11/10 2022 (22H2)" }
            "21H2" { "Windows 11/10 2021 (21H2)" }
            "21H1" { "Windows 10 2021 (21H1)" }
            "20H2" { "Windows 10 2020 (20H2)" }
            "2004" { "Windows 10 2020 (2004)" }
            "1909" { "Windows 10 2019 (1909)" }
            "1809" { "Windows 10 2018 (1809)" }
            default { if ($WinVersion) { "Version $WinVersion" } else { "Unknown Version" } }
        }

        $WinLicense = cscript.exe //nologo "$env:SystemRoot\System32\slmgr.vbs" /dli 2>$null
        $WinStatus = "Unknown"
        $WinKey = "Digital License"

        foreach ($line in $WinLicense) {
            if ($line -match "License Status") { $WinStatus = ($line.Split(":")[1]).Trim() }
            if ($line -match "Partial Product Key") { $WinKey = ($line.Split(":")[1]).Trim() }
        }

        if ($WinStatus -match "Licensed") { $WinCheckStatus = 0; $WinState = "OK" }
        elseif ($WinStatus -match "Unknown") { $WinCheckStatus = 3; $WinState = "UNKNOWN" }
        else { $WinCheckStatus = 2; $WinState = "CRITICAL" }

        $linesWeekly.Add("$WinCheckStatus `"Info_Windows`" - $WinState - OS: $WinName | Version: $WinVersionName | Arch: $WinArch | Build: $WinBuild | License: $WinStatus | Key: $WinKey")
    } catch {}

    # B. OFFICE INVENTORY (MS OFFICE + LIBREOFFICE + WPS OFFICE)
    try {
        $office_list = @()
        $OfficeStatus = "Not Installed"

        # 1. MS Office Check
        $uninstallPaths = @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall", "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall")
        foreach ($unPath in $uninstallPaths) {
            if (-not (Test-Path $unPath)) { continue }
            $keys = Get-ChildItem $unPath -ErrorAction SilentlyContinue
            foreach ($key in $keys) {
                $props = Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue
                $dn = $props.DisplayName
                if ($dn -match "Microsoft (Office|365)" -and $dn -notmatch "MUI|Proof|Filter|Tools|Component|Update|Pack|Telemetry|Teams") {
                    $office_list += $dn; break
                }
            }
            if ($office_list.Count -gt 0) { break }
        }

        # 2. LibreOffice Check
        foreach ($unPath in $uninstallPaths) {
            if (-not (Test-Path $unPath)) { continue }
            $keys = Get-ChildItem $unPath -ErrorAction SilentlyContinue
            foreach ($key in $keys) {
                $props = Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue
                if ($props.DisplayName -match "LibreOffice") {
                    $office_list += "$($props.DisplayName) $($props.DisplayVersion)"; break
                }
            }
        }

        # 3. WPS Office Check
        foreach ($unPath in $uninstallPaths) {
            if (-not (Test-Path $unPath)) { continue }
            $keys = Get-ChildItem $unPath -ErrorAction SilentlyContinue
            foreach ($key in $keys) {
                $props = Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue
                if ($props.DisplayName -match "WPS Office") {
                    $office_list += "WPS Office v$($props.DisplayVersion)"; break
                }
            }
        }

        # Licenses Status Check
        $OfficePaths = @("$env:ProgramFiles\Microsoft Office\Office16\OSPP.VBS", "${env:ProgramFiles(x86)}\Microsoft Office\Office16\OSPP.VBS")
        foreach ($Path in $OfficePaths) {
            if (-not (Test-Path $Path)) { continue }
            $Output = cscript.exe //nologo $Path /dstatus 2>$null
            foreach ($line in $Output) {
                if ($line -match "LICENSE STATUS|STATUS LISENSI") { $OfficeStatus = $line.Replace("LICENSE STATUS:","").Replace("---","").Trim() }
            }
            break
        }

        $final_office_str = if ($office_list.Count -gt 0) { $office_list -join " " } else { "No Office" }

        if ($final_office_str -eq "No Office") { $OfficeCheckStatus = 0; $OfficeState = "OK" }
        elseif ($OfficeStatus -match "Licensed|LICENSED|Click-to-Run" -or $office_list -match "LibreOffice|WPS") { $OfficeCheckStatus = 0; $OfficeState = "OK" }
        else { $OfficeCheckStatus = 0; $OfficeState = "OK" }

        $linesWeekly.Add("$OfficeCheckStatus `"Info_Office`" - OK - Product: $final_office_str | Status: Native Application")
    } catch {}

    # C. RAM HARDWARE INFO (PER SLOT DETAIL FORMAT)
    try {
        $rams = Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue
        $os_mem = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        $total_gb = [math]::Round($os_mem.TotalVisibleMemorySize / 1MB, 2)
        $slot_info_list = @()

        foreach ($ram in $rams) {
            $gb = [math]::Round($ram.Capacity / 1GB, 0)
            $speed = if ($ram.Speed) { "$($ram.Speed) MT/s" } else { "Speed Unknown" }
            $raw_merk = if ($ram.Manufacturer) { $ram.Manufacturer.Trim() } else { "Unknown" }
            $part = if ($ram.PartNumber) { $ram.PartNumber.Trim() } else { "" }

            $merk = $raw_merk
            if ($raw_merk -match "802C|Micron") { $merk = "Micron" } 
            elseif ($raw_merk -match "04CD|Corsair") { $merk = "Corsair" } 
            elseif ($raw_merk -match "7F98|Kingston") { $merk = "Kingston" } 
            elseif ($raw_merk -match "CE00|Samsung") { $merk = "Samsung" } 
            elseif ($raw_merk -match "AD00|Hynix|SK") { $merk = "SK Hynix" } 
            elseif ($raw_merk -match "2C00") { $merk = "Crucial" } 
            elseif ($raw_merk -match "VGEN|V-GEN") { $merk = "V-GEN" } 

            $part_str = if ($part) { "Number: $part" } else { "" }
            $slot_info = "$gb GB ($speed $merk $part_str)".Trim()
            $slot_info_list += $slot_info
        }

        $detail_teks = if ($slot_info_list) { $slot_info_list -join " " } else { "Detail keping tidak diizinkan BIOS" }
        $linesWeekly.Add("0 `"RAM_Hardware_Info`" - Total: $($total_gb) GB -- Slot Info: $($detail_teks)")
    } catch {}

    # D. REMOTE ACCESS ID
    try {
        $users = Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch "^(Public|Default|Default User|All Users)$" }
        $ANYDESK_ID = "Not Installed"; $RUSTDESK_ID = "Not Installed"; $ANYVIEWER_ID = "Not Installed"

        # AnyDesk
        $ad_paths = @("$env:ProgramData\AnyDesk\system.conf")
        foreach ($u in $users) { $ad_paths += "$($u.FullName)\AppData\Roaming\AnyDesk\system.conf" }
        foreach ($path in $ad_paths) {
            if (Test-Path $path) {
                $ad_conf = Get-Content $path -ErrorAction SilentlyContinue
                $ad_line = $ad_conf | Where-Object { $_ -match "^ad\.anynet\.id=" }
                if ($ad_line) { $ANYDESK_ID = ($ad_line -split "=")[1].Trim(); break }
            }
        }

        # RustDesk CLI / Config
        $rd_exe = @("$env:ProgramFiles\RustDesk\rustdesk.exe", "${env:ProgramFiles(x86)}\RustDesk\rustdesk.exe", "$env:LOCALAPPDATA\Programs\RustDesk\rustdesk.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
        if ($rd_exe) {
            $cli_out = (& $rd_exe --get-id 2>$null | Out-String).Trim()
            if ($cli_out -match '^\d{8,15}$') { $RUSTDESK_ID = $cli_out }
        }

        if ($RUSTDESK_ID -eq "Not Installed") {
            $rd_paths = @("$env:ProgramData\RustDesk\config\RustDesk2.toml", "$env:ProgramData\RustDesk\config\RustDesk.toml")
            foreach ($u in $users) { $rd_paths += "$($u.FullName)\AppData\Roaming\RustDesk\config\RustDesk2.toml" }
            foreach ($path in $rd_paths) {
                if (Test-Path $path) {
                    $content = Get-Content $path -Raw -ErrorAction SilentlyContinue
                    if ($content -match '(?m)^\s*id\s*=\s*[''"]?(\d{8,15})[''"]?') { $RUSTDESK_ID = $matches[1].Trim(); break }
                }
            }
        }

        $linesWeekly.Add("0 `"Remote_Access_ID`" - OK: AnyDesk: $ANYDESK_ID | RustDesk: $RUSTDESK_ID (Windows Platform)")
    } catch {}

    Save-CacheAndOutput -FilePath $WeeklyCache -Lines $linesWeekly
} else {
    Read-CacheAndOutput -FilePath $WeeklyCache
}


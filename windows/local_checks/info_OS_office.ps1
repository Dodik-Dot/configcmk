# =====================================================================
# Local Check Checkmk: Daily OS & Multi-Office Suite License Check (Windows)
# Scheduled to run once a day at 16:00
# =====================================================================
$ErrorActionPreference = 'SilentlyContinue'
$CacheDir = "$env:ProgramData\checkmk\agent\cache"
if (-not (Test-Path $CacheDir)) { New-Item -ItemType Directory -Force $CacheDir | Out-Null }
$CacheFile = Join-Path $CacheDir "cache_os_office.txt"

# Logika Penjadwalan: Eksekusi Baru Setiap Hari Setelah Pukul 16:00
$Now = Get-Date
$Today16 = Get-Date -Hour 16 -Minute 0 -Second 0
if ($Now -lt $Today16) {
    $Last16 = $Today16.AddDays(-1)
} else {
    $Last16 = $Today16
}

$NeedUpdate = $true
if (Test-Path $CacheFile) {
    $CacheMtime = (Get-Item $CacheFile).LastWriteTime
    if ($CacheMtime -ge $Last16) {
        $NeedUpdate = $false
    }
}

if ($NeedUpdate) {
    $Lines = [System.Collections.Generic.List[string]]::new()
    
    # =================================================================
    # 1. PENGECEKAN WINDOWS OS (Info_OS)
    # =================================================================
    try {
        $OS = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        $WinName = $OS.Caption
        $WinArch = $OS.OSArchitecture
        $WinBuild = $OS.BuildNumber

        $WinDisplayVer = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue).DisplayVersion
        $WinVersionName = switch ($WinDisplayVer) {
            "25H2" { "Windows 11 2025 (25H2)" }
            "25H1" { "Windows 11 2025 (25H1)" }
            "24H2" { "Windows 11 2024 (24H2)" }
            "23H2" { "Windows 11 2023 (23H2)" }
            "22H2" { if ($WinName -match "11") { "Windows 11 2022 (22H2)" } else { "Windows 10 2022 (22H2)" } }
            "21H2" { if ($WinName -match "11") { "Windows 11 2021 (21H2)" } else { "Windows 10 2021 (21H2)" } }
            "21H1" { "Windows 10 2021 (21H1)" }
            "20H2" { "Windows 10 2020 (20H2)" }
            "2004" { "Windows 10 2020 (2004)" }
            "1909" { "Windows 10 2019 (1909)" }
            default { if ($WinDisplayVer) { "Version $WinDisplayVer" } else { "Version $WinBuild" } }
        }

        $WinLicense = cscript.exe //nologo "$env:SystemRoot\System32\slmgr.vbs" /dli 2>$null
        $WinStatus = "Unknown"
        $WinKey = "Digital License"

        foreach ($line in $WinLicense) {
            if ($line -match "License Status") { $WinStatus = ($line.Split(":")[1]).Trim() }
            if ($line -match "Partial Product Key") { $WinKey = ($line.Split(":")[1]).Trim() }
        }

        $WinCheckStatus = 0
        $WinState = "OK"
        if ($WinStatus -match "Licensed") { 
            $WinCheckStatus = 0; $WinState = "OK" 
        } elseif ($WinStatus -match "Unknown") { 
            $WinCheckStatus = 0; $WinState = "OK" 
        } else { 
            $WinCheckStatus = 2; $WinState = "CRITICAL" 
        }

        $Lines.Add("$WinCheckStatus `"Info_OS`" - $WinState - OS: $WinName | Version: $WinVersionName | Arch: $WinArch | Build: $WinBuild | License: $WinStatus | Key: $WinKey")
    } catch {
        $Lines.Add("0 `"Info_OS`" - OK - OS: Microsoft Windows | Status: Error querying WMI")
    }

    # =================================================================
    # 2. PENGECEKAN MULTI-OFFICE & STANDALONE (Info_Office)
    # =================================================================
    try {
        $OfficeList = [System.Collections.Generic.List[string]]::new()
        $OtherList  = [System.Collections.Generic.List[string]]::new()

       # A. Deteksi Click-to-Run (C2R) Apps & Suites
        $CtrPath = "HKLM:\Software\Microsoft\Office\ClickToRun\Configuration"
        if (Test-Path $CtrPath) {
            $ReleaseIDs = Get-ItemPropertyValue -Path $CtrPath -Name "ProductReleaseIDs" -ErrorAction SilentlyContinue
            $VerReport  = Get-ItemPropertyValue -Path $CtrPath -Name "VersionToReport" -ErrorAction SilentlyContinue
            if ($ReleaseIDs) {
                $c2rItems = $ReleaseIDs -split ","
                foreach ($item in $c2rItems) {
                    $cleanItem = $item.Trim()
                    $label = switch -Wildcard ($cleanItem) {
                        "*O365*"                                { "Microsoft 365" }
                        "*ProPlus2024*"                         { "Office Pro Plus 2024" }
                        "*ProPlus2021*"                         { "Office Pro Plus 2021" }
                        "*ProPlus2019*"                         { "Office Pro Plus 2019" }
                        "*ProPlus2016*"                         { "Office Pro Plus 2016" }
                        "*Excel2024*"                           { "Microsoft Excel 2024 LTSC" }
                        "*ExcelLTSC*"                           { "Microsoft Excel 2024 LTSC" }
                        "*Excel2021*"                           { "Microsoft Excel 2021" }
                        "*Excel2019*"                           { "Microsoft Excel 2019" }
                        "*Excel2016*"                           { "Microsoft Excel 2016" }
                        "*Excel*"                               { "Microsoft Excel 2024 LTSC" }
                        "*Word*"                                { "Microsoft Word (Standalone)" }
                        "*Visio*"                               { "Microsoft Visio" }
                        "*Project*"                             { "Microsoft Project" }
                        default                                 { $cleanItem }
                    }
                    $c2rTag = if ($VerReport) { "$label (v$VerReport)" } else { $label }
                    if (-not $OfficeList.Contains($c2rTag)) { $OfficeList.Add($c2rTag) }
                }
            }
        }

        # B. Pindai Registry Uninstall (MSI & Alternatif) + Anti-Duplikasi
        $RegPaths = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )
        $InstalledApps = Get-ItemProperty $RegPaths -ErrorAction SilentlyContinue
        $ExcludePattern = "MUI|Proof|Filter|Tools|Component|Update|Pack|Telemetry|Teams|Licensing|Primary Interop|Visual Studio|Add-in|Language|Service Pack|Help|Outils|Herramientas|Correcci|Vérification|Verificacion"

        foreach ($app in $InstalledApps) {
            $dn = $app.DisplayName
            $dv = $app.DisplayVersion
            if (-not $dn) { continue }

            if ($dn -match "^Microsoft\s+(Office|Excel|Word|PowerPoint|Access|Outlook|Publisher|Visio|Project)" -and 
                $dn -notmatch $ExcludePattern) {
                
                $cleanName = ($dn -replace '\s*-\s*[a-z]{2}-[a-z]{2}$', '').Trim()
                if ($cleanName -match "Excel LTSC") { $cleanName = "Microsoft Excel 2024 LTSC" }
                $itemWithVer = if ($dv) { "$cleanName (v$dv)" } else { $cleanName }
                
                # Cegah duplikasi jika sudah terdeteksi di langkah Click-to-Run
                $exists = $false
                foreach ($known in $OfficeList) {
                    if ($known -like "*$cleanName*" -or ($known -like "*Excel*" -and $cleanName -like "*Excel*")) { 
                        $exists = $true
                        break 
                    }
                }
                if (-not $exists) { $OfficeList.Add($itemWithVer) }
            }
            elseif ($dn -match "^LibreOffice") {
                $lo = if ($dv) { "$dn $dv" } else { $dn }
                if (-not ($OtherList | Where-Object { $_ -like "*LibreOffice*" })) { $OtherList.Add($lo.Trim()) }
            }
            elseif ($dn -match "WPS Office" -and $dn -notmatch $ExcludePattern) {
                $wps = if ($dv) { "WPS Office v$dv" } else { "WPS Office" }
                if (-not ($OtherList | Where-Object { $_ -like "*WPS Office*" })) { $OtherList.Add($wps.Trim()) }
            }
        }
        
        # C. Pindai Lisensi OSPP.VBS (Diurutkan dari Office 2010 -> 2013 -> 2016/C2R)
        $AllLicenses = [System.Collections.Generic.List[string]]::new()
        $VbsSearchPaths = @(
            "$env:ProgramFiles\Microsoft Office\Office14\OSPP.VBS",
            "${env:ProgramFiles(x86)}\Microsoft Office\Office14\OSPP.VBS",
            "$env:ProgramFiles\Microsoft Office\Office15\OSPP.VBS",
            "${env:ProgramFiles(x86)}\Microsoft Office\Office15\OSPP.VBS",
            "$env:ProgramFiles\Microsoft Office\Office16\OSPP.VBS",
            "${env:ProgramFiles(x86)}\Microsoft Office\Office16\OSPP.VBS"
        ) | Where-Object { Test-Path $_ } | Select-Object -Unique

        foreach ($vPath in $VbsSearchPaths) {
            $CscriptOut = cscript.exe //nologo "$vPath" /dstatus 2>$null
            $currentStatus = ""
            $currentKey = ""

            foreach ($line in $CscriptOut) {
                if ($line -match "LICENSE STATUS:\s*---(.*?)---") {
                    $currentStatus = $Matches[1].Trim()
                } elseif ($line -match "LICENSE STATUS:\s*(.*)") {
                    $currentStatus = $Matches[1].Trim()
                }

                if ($line -match "Last 5 characters of installed product key:\s*(.*)") {
                    $currentKey = $Matches[1].Trim()
                    if ($currentStatus) {
                        $licEntry = "$currentStatus (Key: $currentKey)"
                        if (-not $AllLicenses.Contains($licEntry)) {
                            $AllLicenses.Add($licEntry)
                        }
                        $currentStatus = ""
                        $currentKey = ""
                    }
                }
            }
        }

        # D. Format Output Akhir Checkmk
        $TotalOffice = [System.Collections.Generic.List[string]]::new()
        foreach ($o in $OfficeList) { $TotalOffice.Add($o) }
        foreach ($ot in $OtherList) { $TotalOffice.Add($ot) }

        if ($TotalOffice.Count -gt 0) {
            $ProductString = $TotalOffice -join " + "
            $LicenseString = if ($AllLicenses.Count -gt 0) { $AllLicenses -join " + " } else { "N/A" }
            $Lines.Add("0 `"Info_Office`" - OK - Product: $ProductString | License: $LicenseString")
        } else {
            $Lines.Add("0 `"Info_Office`" - OK - Product: Tidak ada aplikasi Office (Native Windows) | Status: OK")
        }
    } catch {
        $Lines.Add("0 `"Info_Office`" - OK - Product: Microsoft Office | Status: Error checking registry")
    }

    # Simpan hasil pemindaian ke file cache
    [System.IO.File]::WriteAllLines($CacheFile, $Lines, [System.Text.Encoding]::UTF8)
}

# Tampilkan hasil dari file cache
if (Test-Path $CacheFile) {
    [System.IO.File]::ReadAllLines($CacheFile, [System.Text.Encoding]::UTF8)
}

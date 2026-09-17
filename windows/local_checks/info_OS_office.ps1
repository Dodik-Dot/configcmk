# =====================================================================
# Local Check Checkmk: Daily OS & Office Suite License Check (Windows)
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
        $Lines.Add("0 `"Info_Windows`" - OK - OS: Microsoft Windows | Status: Error querying WMI")
    }

    # =================================================================
    # 2. PENGECEKAN OFFICE SUITE (Info_Office)
    # =================================================================
    try {
        $OfficeProduct = "Tidak terpasang"
        $OfficeVersion = ""
        $OfficeYear = ""
        $OfficeLicense = "N/A"
        $OfficeKey = "N/A"
        $OtherOfficeList = @()

        # A. Cek Click-to-Run (Office 365, Office 2019, 2021, 2024, Standalone Apps)
        $CtrPath = "HKLM:\Software\Microsoft\Office\ClickToRun\Configuration"
        if (Test-Path $CtrPath) {
            $ReleaseIDs = Get-ItemPropertyValue -Path $CtrPath -Name "ProductReleaseIDs" -ErrorAction SilentlyContinue
            $VerReport = Get-ItemPropertyValue -Path $CtrPath -Name "VersionToReport" -ErrorAction SilentlyContinue
            if ($ReleaseIDs) {
                $OfficeProduct = "Microsoft 365 (Click-to-Run)"
                $OfficeVersion = $VerReport
                
                $yearTags = @()
                if ($ReleaseIDs -match "365|O365") { $yearTags += "Microsoft 365" }
                if ($ReleaseIDs -match "2024") { $yearTags += "Office 2024" }
                if ($ReleaseIDs -match "2021") { $yearTags += "Office 2021" }
                if ($ReleaseIDs -match "2019") { $yearTags += "Office 2019" }
                if ($ReleaseIDs -match "2016") { $yearTags += "Office 2016" }
                if ($ReleaseIDs -match "Excel") { $yearTags += "Excel 2021" }
                
                if ($yearTags.Count -gt 0) {
                    $OfficeYear = ($yearTags | Select-Object -Unique) -join " / "
                } else {
                    $OfficeYear = $ReleaseIDs
                }
            }
        }

        # B. Cek MSI Registry & Alternatif Office (LibreOffice, WPS Office)
        $RegPaths = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )
        $InstalledApps = Get-ItemProperty $RegPaths -ErrorAction SilentlyContinue

        foreach ($app in $InstalledApps) {
            $dn = $app.DisplayName
            $dv = $app.DisplayVersion
            if (-not $dn) { continue }

            if ($OfficeProduct -eq "Tidak terpasang" -and $dn -match "Microsoft (Office|365)" -and $dn -notmatch "MUI|Proof|Filter|Tools|Component|Update|Pack|Telemetry|Teams") {
                $OfficeProduct = $dn
                $OfficeVersion = $dv
                $OfficeYear = $dn
            } elseif ($dn -match "LibreOffice") {
                $OtherOfficeList += "$dn $dv".Trim()
            } elseif ($dn -match "WPS Office") {
                $OtherOfficeList += "WPS Office v$dv".Trim()
            }
        }

        # C. Cek Status Lisensi via OSPP.VBS
        $VbsPaths = @(
            "$env:ProgramFiles\Microsoft Office\Office16\OSPP.VBS",
            "${env:ProgramFiles(x86)}\Microsoft Office\Office16\OSPP.VBS",
            "$env:ProgramFiles\Microsoft Office\Office15\OSPP.VBS",
            "${env:ProgramFiles(x86)}\Microsoft Office\Office15\OSPP.VBS"
        )
        $VbsPath = $VbsPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

        if ($VbsPath) {
            $CscriptOut = cscript.exe //nologo "$VbsPath" /dstatus 2>$null
            foreach ($line in $CscriptOut) {
                if ($line -match "LICENSE STATUS:\s*---(.*?)---") {
                    $OfficeLicense = $Matches[1].Trim()
                } elseif ($line -match "LICENSE STATUS:\s*(.*)") {
                    $OfficeLicense = $Matches[1].Trim()
                }
                if ($line -match "Last 5 characters of installed product key:\s*(.*)") {
                    $OfficeKey = $Matches[1].Trim()
                }
            }
        }

        # D. Format Output Sesuai Standar Monitoring
        if ($OfficeProduct -ne "Tidak terpasang") {
            $YearPart = if ($OfficeYear) { " | Year: $OfficeYear" } else { "" }
            $VerPart = if ($OfficeVersion) { " | Version: $OfficeVersion" } else { "" }
            $Lines.Add("0 `"Info_Office`" - OK - Product: $OfficeProduct$YearPart$VerPart | License: $OfficeLicense | Key: $OfficeKey")
        } elseif ($OtherOfficeList.Count -gt 0) {
            $OtherJoined = $OtherOfficeList -join " + "
            $Lines.Add("0 `"Info_Office`" - OK - Product: $OtherJoined | Status: Native Application")
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

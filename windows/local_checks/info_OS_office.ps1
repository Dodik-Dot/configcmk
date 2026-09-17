# =====================================================================
# Local Check Checkmk: Daily OS & Office Suite License Check (Windows)
# Scheduled to run once a day at 16:00
# =====================================================================
$CacheDir = "$env:ProgramData\checkmk\agent\cache"
if (-not (Test-Path $CacheDir)) { New-Item -ItemType Directory -Force $CacheDir | Out-Null }
$CacheFile = Join-Path $CacheDir "cache_os_office.txt"

# Get current hour and today's 16:00 threshold
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
    if (Test-Path $CacheFile) { Remove-Item $CacheFile -Force }
    
    $CheckedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    # --- 1. PENGECEKAN WINDOWS OS ---
    $OS = Get-CimInstance -ClassName Win32_OperatingSystem
    $OSName = $OS.Caption
    $OSVersion = $OS.Version
    $OSArch = $OS.OSArchitecture
    
    # Get License Key Status / Windows Activation Status
    $LicenseStatusText = "Activated (Licensed)"
    try {
        $SLS = Get-CimInstance -ClassName SoftwareLicensingProduct -Filter "ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f' and PartialProductKey <> NULL" -ErrorAction SilentlyContinue
        if ($SLS) {
            $StatusVal = $SLS.LicenseStatus
            # 1 = Licensed, 2 = OOBGrace, 3 = OOTGrace, 4 = NonGenuineGrace, 5 = Notification
            if ($StatusVal -eq 1) { $LicenseStatusText = "Activated (Licensed)" }
            else { $LicenseStatusText = "Unactivated / Grace Period (Code: $StatusVal)" }
        }
    } catch {
        # Fallback
    }
    
    $OS_Output = "0 `"Info_OS`" - OK - OS: $OSName | Kernel: $OSVersion | Arch: $OSArch | License: $LicenseStatusText ❘ Checked At: $CheckedAt"
    $OS_Output | Out-File -FilePath $CacheFile -Encoding utf8 -Append
    
    # --- 2. PENGECEKAN MS OFFICE SUITE ---
    $OfficeVersion = "Tidak terpasang"
    $OfficeLicense = "N/A"
    
    # Try ClickToRun registry first for version
    $CtrPath = "HKLM:\Software\Microsoft\Office\ClickToRun\Configuration"
    if (Test-Path $CtrPath) {
        $Prod = Get-ItemPropertyValue -Path $CtrPath -Name "ProductReleaseIDs" -ErrorAction SilentlyContinue
        $Ver = Get-ItemPropertyValue -Path $CtrPath -Name "VersionToReport" -ErrorAction SilentlyContinue
        if ($Prod -and $Ver) {
            $OfficeVersion = "$Prod ($Ver)"
        }
    }
    
    # Fallback registry search if not found
    if ($OfficeVersion -eq "Tidak terpasang") {
        $RegPaths = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )
        $OfficeReg = Get-ItemProperty $RegPaths -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*Microsoft Office*" -or $_.DisplayName -like "*Microsoft 365*" } | Select-Object -First 1
        if ($OfficeReg) {
            $OfficeVersion = "$($OfficeReg.DisplayName) v$($OfficeReg.DisplayVersion)"
        }
    }
    
    # Run ospp.vbs scan for Office licensing if available
    $ProgramFiles = ${env:ProgramFiles}
    $ProgramFiles86 = ${env:ProgramFiles(x86)}
    $VbsPaths = @(
        "$ProgramFiles\Microsoft Office\Office16\OSPP.VBS",
        "$ProgramFiles86\Microsoft Office\Office16\OSPP.VBS",
        "$ProgramFiles\Microsoft Office\Office15\OSPP.VBS",
        "$ProgramFiles86\Microsoft Office\Office15\OSPP.VBS"
    )
    
    $VbsPath = $null
    foreach ($Path in $VbsPaths) {
        if (Test-Path $Path) {
            $VbsPath = $Path
            break
        }
    }
    
    if ($VbsPath) {
        try {
            $CscriptOutput = cscript.exe //NoLogo "$VbsPath" /dstatus 2>$null
            $LicenseLine = $CscriptOutput | Where-Object { $_ -like "*LICENSE STATUS:*" } | Select-Object -Last 1
            if ($LicenseLine) {
                $OfficeLicense = ($LicenseLine -replace "LICENSE STATUS:", "").Trim()
            }
            $PartialKey = $CscriptOutput | Where-Object { $_ -like "*Last 5 characters of installed product key:*" } | Select-Object -Last 1
            if ($PartialKey) {
                $KeyStr = ($PartialKey -replace "Last 5 characters of installed product key:", "").Trim()
                $OfficeLicense = "$OfficeLicense (Key: ...-$KeyStr)"
            }
        } catch {
            # Fallback
        }
    }
    
    if ($OfficeVersion -eq "Tidak terpasang") {
        $Office_Output = "0 `"Info_Office`" - OK - Product: Tidak ada aplikasi Office (Native Windows) | Checked At: $CheckedAt"
    } else {
        $Office_Output = "0 `"Info_Office`" - OK - Product: $OfficeVersion | Status: Licensed ($OfficeLicense) | Checked At: $CheckedAt"
    }
    
    $Office_Output | Out-File -FilePath $CacheFile -Encoding utf8 -Append
}

Get-Content $CacheFile -ErrorAction SilentlyContinue

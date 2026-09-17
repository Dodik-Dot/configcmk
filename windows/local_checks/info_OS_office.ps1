# =====================================================================
# Local Check Checkmk: Daily OS & Office Suite License Check (Windows)
# Scheduled to run once a day at 16:00
# =====================================================================
$ErrorActionPreference = 'SilentlyContinue'
$CacheFolder = "$env:ProgramData\checkmk\agent\cache"
if (-not (Test-Path $CacheFolder)) { New-Item -ItemType Directory -Path $CacheFolder -Force | Out-Null }
$CacheFile = "$CacheFolder\cache_os_office_info.txt"

$Today = Get-Date
$Today16 = $Today.Date.AddHours(16)
$Last16 = if ($Today.Hour -lt 16) { $Today16.AddDays(-1) } else { $Today16 }

$NeedUpdate = $true
if (Test-Path $CacheFile) {
    if ((Get-Item $CacheFile).LastWriteTime -ge $Last16) { $NeedUpdate = $false }
}

if ($NeedUpdate) {
    $lines = [System.Collections.Generic.List[string]]::new()
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    # OS Info
    $os = Get-CimInstance Win32_OperatingSystem
    $os_name = $os.Caption
    $os_build = $os.BuildNumber
    $os_arch = $os.OSArchitecture
    $lines.Add("0 `"Info_OS`" - OK - OS: $os_name | Kernel: $os_build | Arch: $os_arch ❘ Checked At: $timestamp")

    # Office Info (MS Office + LibreOffice + WPS + OnlyOffice)
    $office_list = @()
    $uninstallPaths = @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall", "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall")

    foreach ($path in $uninstallPaths) {
        if (-not (Test-Path $path)) { continue }
        $keys = Get-ChildItem $path -ErrorAction SilentlyContinue
        foreach ($k in $keys) {
            $p = Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue
            $dn = $p.DisplayName
            $dv = $p.DisplayVersion

            if ($dn -match "Microsoft (Office|365)" -and $dn -notmatch "MUI|Proof|Filter|Tools|Component|Update|Pack|Teams") {
                if ($office_list -notcontains $dn) { $office_list += $dn }
            } elseif ($dn -match "LibreOffice") {
                $item = "$dn $dv".Trim()
                if ($office_list -notcontains $item) { $office_list += $item }
            } elseif ($dn -match "WPS Office") {
                $item = "WPS Office v$dv".Trim()
                if ($office_list -notcontains $item) { $office_list += $item }
            } elseif ($dn -match "ONLYOFFICE") {
                $item = "Onlyoffice v$dv".Trim()
                if ($office_list -notcontains $item) { $office_list += $item }
            }
        }
    }

    $final_office = if ($office_list.Count -gt 0) { $office_list -join " + " } else { "Tidak ada aplikasi Office" }
    $lines.Add("0 `"Info_Office`" - OK - Product: $final_office | Status: Native Windows Application ❘ Checked At: $timestamp")

    [System.IO.File]::WriteAllLines($CacheFile, $lines, [System.Text.Encoding]::UTF8)
    foreach ($l in $lines) { Write-Host $l }
} else {
    if (Test-Path $CacheFile) { Get-Content $CacheFile }
}

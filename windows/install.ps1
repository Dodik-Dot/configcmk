# =============================================================================
# Checkmk Agent Bootstrap Installer - Windows PowerShell Edition
# Repositori : Dodik-Dot/configcmk
# Kompatibel : Windows 10/11 & Windows Server 2016/2019/2022/2025
# Fitur      : LibreHardwareMonitorLib, HW/SW Inventory, & 11 Local Checks
# =============================================================================

#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [Alias("s", "server")]
    [string]$ServerIP = "",

    [Alias("p", "port")]
    [string]$WebPort = "80",

    [Alias("d", "site")]
    [string]$SiteID = "cmk",

    [Alias("v", "version")]
    [string]$AgentVersion = "2.5.0p14-1",

    [Alias("g", "github")]
    [string]$GithubRepo = "Dodik-Dot/configcmk",

    [Alias("b", "branch")]
    [string]$Branch = "main"
)

# 1. Pastikan script berjalan sebagai Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[ERROR] Script ini HARUS dijalankan via PowerShell 'Run as Administrator'!" -ForegroundColor Red
    Exit 1
}

# Paksa penggunaan TLS 1.2 dan TLS 1.3
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls13

# Fungsi sanitasi input server
function Format-ServerInput {
    param([string]$inputRaw, [string]$currentPort, [string]$currentSite)
    
    $clean =$inputRaw.Trim()
    # Hapus prefix http:// atau https:// jika ada
    $clean =$clean -replace '^https?://', ''
    
    # Deteksi jika ada path site (contoh: 192.168.122.205/cmk)
    if ($clean -match '^([^/]+)/([^/]+)/?.*$') {$clean = $Matches[1]$currentSite = $Matches[2] } else {$clean = $clean -replace '/.*$', ''
    }
    
    # Deteksi jika ada port (contoh: 192.168.55.112:8081)
    if ($clean -match '^([^:]+):(\d+)$') {
        $hostOnly =$Matches[1]
        $portOnly =$Matches[2]
    } else {
        $hostOnly =$clean
        $portOnly =$currentPort
    }

    return @{
        Host = $hostOnly
        Port = $portOnly
        Site = $currentSite
    }
}

# 2. Mode Interaktif jika ServerIP belum diisi
if ([string]::IsNullOrWhiteSpace($ServerIP)) {
    Write-Host "`n=== Konfigurasi Server Checkmk ===" -ForegroundColor Cyan
    Write-Host "Contoh input:" -ForegroundColor Gray
    Write-Host "  - Cabang Madiun (Port Mapping) : 192.168.122.205" -ForegroundColor Gray
    Write-Host "  - Cabang Kediri (Port Khusus)  : 192.168.55.112:8081`n" -ForegroundColor Gray
    
    $PromptServer = Read-Host "Masukkan IP/Hostname Server Checkmk"
    if ([string]::IsNullOrWhiteSpace($PromptServer)) {
        Write-Host "[ERROR] IP address / hostname server Checkmk wajib diisi!" -ForegroundColor Red
        Exit 1
    }
    
    $parsed = Format-ServerInput -inputRaw$PromptServer -currentPort $WebPort -currentSite$SiteID
    $ServerIP =$parsed.Host
    $WebPort  =$parsed.Port
    $SiteID   =$parsed.Site

    $PromptPort = Read-Host "Masukkan Web Port Checkmk [Default: $WebPort]"
    if (-not [string]::IsNullOrWhiteSpace($PromptPort)) { $WebPort =$PromptPort.Trim() }

    $PromptSite = Read-Host "Masukkan Site ID Checkmk [Default: $SiteID]"
    if (-not [string]::IsNullOrWhiteSpace($PromptSite)) { $SiteID =$PromptSite.Trim() }

    $PromptVer = Read-Host "Masukkan Versi Agen Checkmk [Default: $AgentVersion]"
    if (-not [string]::IsNullOrWhiteSpace($PromptVer)) { $AgentVersion =$PromptVer.Trim() }
} else {
    $parsed = Format-ServerInput -inputRaw$ServerIP -currentPort $WebPort -currentSite$SiteID
    $ServerIP =$parsed.Host
    $WebPort  =$parsed.Port
    $SiteID   =$parsed.Site
}

# 3. Bentuk Base URL Server
$PortSuffix = if ($WebPort -eq "80" -or [string]::IsNullOrWhiteSpace($WebPort)) { "" } else { ":$WebPort" }
$BaseServerUrl = "http://${ServerIP}${PortSuffix}"

# 4. Tampilkan Ringkasan Konfigurasi
Write-Host "`n*** Ringkasan Konfigurasi Target ***" -ForegroundColor Green
Write-Host "Server Host : $ServerIP"
Write-Host "Web Port    : $WebPort"
Write-Host "Site ID     : $SiteID"
Write-Host "Versi Agen  : $AgentVersion"
Write-Host "Base URL    : $BaseServerUrl/$SiteID"
Write-Host "GitHub Repo : $GithubRepo ($Branch)`n"

# 5. Siapkan Struktur Direktori Agen
$AgentDir   = "$env:ProgramData\checkmk\agent"
$LocalDir   = "$AgentDir\local"
$PluginsDir = "$AgentDir\plugins"
$LibDir     = "$AgentDir\lib"
$CacheDir   = "$AgentDir\cache"

Write-Host "[INFO] Menyiapkan folder agen di $AgentDir..." -ForegroundColor Yellow
@($LocalDir,$PluginsDir, $LibDir,$CacheDir) | ForEach-Object {
    if (-not (Test-Path $_)) { New-Item -ItemType Directory -Path$_ -Force | Out-Null }
}

Write-Host "[INFO] Membersihkan skrip dan cache lama..." -ForegroundColor Yellow
Remove-Item -Path "$LocalDir\*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$CacheDir\*" -Recurse -Force -ErrorAction SilentlyContinue

# 6. Unduh dan Pasang Installer Agen (.msi)
$MsiFileName = "check-mk-agent-${AgentVersion}.msi"
$MsiUrl      = "${BaseServerUrl}/${SiteID}/check_mk/agents/${MsiFileName}"
$TempMsiPath = "$env:TEMP\$MsiFileName"

Write-Host "`n[INFO] Mengunduh installer Agen Checkmk dari $MsiUrl..." -ForegroundColor Yellow
try {
    Invoke-WebRequest -Uri $MsiUrl -OutFile $TempMsiPath -UseBasicParsing -TimeoutSec 60
    Write-Host "[SUCCESS] Installer MSI berhasil diunduh." -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Gagal mengunduh file agen .msi dari URL:" -ForegroundColor Red
    Write-Host "        $MsiUrl" -ForegroundColor Red
    Write-Host "Detail Error : $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "`nTips Troubleshooting:" -ForegroundColor Yellow
    Write-Host "1. Pastikan port ($WebPort) dan Site ($SiteID) dapat diakses." -ForegroundColor Yellow
    Write-Host "2. Uji akses via browser: $MsiUrl" -ForegroundColor Yellow
    Exit 1
}

Write-Host "[INFO] Memasang / Memperbarui Agen Checkmk via msiexec..." -ForegroundColor Yellow
try {
    $proc = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$TempMsiPath`" /qn /norestart ALLUSERS=1" -Wait -PassThru
    if ($proc.ExitCode -eq 0 -or$proc.ExitCode -eq 3010) {
        Write-Host "[SUCCESS] Agen Checkmk berhasil dipasang!" -ForegroundColor Green
    } else {
        Write-Host "[WARNING] msiexec selesai dengan Exit Code: $($proc.ExitCode)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "[WARNING] Gagal menjalankan proses instalasi MSI: $($_.Exception.Message)" -ForegroundColor Yellow
} finally {
    Remove-Item -Path $TempMsiPath -Force -ErrorAction SilentlyContinue
}

# 7. Unduh Library LibreHardwareMonitorLib.dll
$DllPath = "$LibDir\LibreHardwareMonitorLib.dll"
$DllUrl  = "https://raw.githubusercontent.com/${GithubRepo}/${Branch}/windows/lib/LibreHardwareMonitorLib.dll"

Write-Host "`n[INFO] Memeriksa pustaka LibreHardwareMonitorLib.dll..." -ForegroundColor Yellow
try {
    Invoke-WebRequest -Uri $DllUrl -OutFile $DllPath -UseBasicParsing -TimeoutSec 30
    Unblock-File -Path $DllPath -ErrorAction SilentlyContinue
    Write-Host "[SUCCESS] LibreHardwareMonitorLib.dll berhasil dipasang." -ForegroundColor Green
} catch {
    Write-Host "[WARNING] Gagal mengunduh LibreHardwareMonitorLib.dll dari GitHub." -ForegroundColor Yellow
}

# 8. Unduh Plugin HW/SW Inventory (mk_inventory.vbs & win_license.bat)
Write-Host "`n[INFO] Mengunduh plugin Hardware/Software Inventory..." -ForegroundColor Yellow
$PluginInventoryPath = "$PluginsDir\mk_inventory.vbs"
$PluginLicensePath   = "$PluginsDir\win_license.bat"
$GithubBaseWindows   = "https://raw.githubusercontent.com/${GithubRepo}/${Branch}/windows"

# mk_inventory.vbs
try {
    $InvUrl = "$GithubBaseWindows/plugins/mk_inventory.vbs?v=$((Get-Date).Ticks)"
    Invoke-WebRequest -Uri $InvUrl -OutFile$PluginInventoryPath -UseBasicParsing -TimeoutSec 30
    Write-Host "[SUCCESS] mk_inventory.vbs berhasil dipasang dari GitHub." -ForegroundColor Green
} catch {
    Write-Host "[WARNING] Mengambil mk_inventory.vbs langsung dari Server Checkmk..." -ForegroundColor Yellow
    try {
        $ServerInvUrl = "${BaseServerUrl}/${SiteID}/check_mk/agents/plugins/mk_inventory.vbs"
        Invoke-WebRequest -Uri $ServerInvUrl -OutFile$PluginInventoryPath -UseBasicParsing -TimeoutSec 30
        Write-Host "[SUCCESS] mk_inventory.vbs berhasil dipasang dari Server Checkmk." -ForegroundColor Green
    } catch {
        Write-Host "[WARNING] Gagal mengunduh mk_inventory.vbs." -ForegroundColor Yellow
    }
}

# win_license.bat
try {
    $LicUrl = "$GithubBaseWindows/plugins/win_license.bat?v=$((Get-Date).Ticks)"
    Invoke-WebRequest -Uri $LicUrl -OutFile$PluginLicensePath -UseBasicParsing -TimeoutSec 30
    Write-Host "[SUCCESS] win_license.bat berhasil dipasang dari GitHub." -ForegroundColor Green
} catch {
    Write-Host "[WARNING] Gagal mengunduh win_license.bat dari GitHub." -ForegroundColor Yellow
}

# 9. Unduh 11 Script Local Checks Windows
Write-Host "`n[INFO] Mengunduh script local checks kustom dari GitHub..." -ForegroundColor Yellow
$LocalChecks = @(
    "battery_health.ps1",
    "cpu_info.ps1",
    "disk_nvme_health.ps1",
    "fan_health.ps1",
    "info_network.ps1",
    "info_OS_office.ps1",
    "ram_health.ps1",
    "ram_usage.ps1",
    "remote_access_id.ps1",
    "remote_apps.ps1",
    "storage_usage.ps1"
)

foreach ($script in $LocalChecks) {
    $ScriptUrl = "$GithubBaseWindows/local_checks/$script`?v=$((Get-Date).Ticks)"
    $DestFile  = "$LocalDir\$script"
    
    try {
        Invoke-WebRequest -Uri $ScriptUrl -OutFile$DestFile -UseBasicParsing -TimeoutSec 20
        Unblock-File -Path $DestFile -ErrorAction SilentlyContinue
        Write-Host "  [+] Berhasil memasang: $script" -ForegroundColor Green
    } catch {
        Write-Host "  [-] Gagal mengunduh: $script" -ForegroundColor Yellow
    }
}

# 10. Konfigurasi Windows Firewall (Inbound Port TCP 6556)
Write-Host "`n[INFO] Mengonfigurasi Windows Firewall (Port TCP 6556 Inbound)..." -ForegroundColor Yellow
try {
    $rule = Get-NetFirewallRule -DisplayName "Checkmk Agent (TCP 6556)" -ErrorAction SilentlyContinue
    if (-not $rule) {
        New-NetFirewallRule -DisplayName "Checkmk Agent (TCP 6556)" -Direction Inbound -LocalPort 6556 -Protocol TCP -Action Allow | Out-Null
    }
    Write-Host "[SUCCESS] Rule Firewall TCP 6556 aktif." -ForegroundColor Green
} catch {
    Write-Host "[WARNING] Pengaturan firewall otomatis dilewati atau gagal: $($_.Exception.Message)" -ForegroundColor Yellow
}

# 11. Restart Service CheckMkService
Write-Host "[INFO] Memastikan layanan CheckMkService berjalan..." -ForegroundColor Yellow
try {
    $svc = Get-Service -Name "CheckMkService" -ErrorAction SilentlyContinue
    if ($svc) {
        Restart-Service -Name "CheckMkService" -Force
        Write-Host "[SUCCESS] Layanan CheckMkService berhasil dimulai ulang." -ForegroundColor Green
    }
} catch {
    Write-Host "[WARNING] Gagal me-restart CheckMkService otomatis: $($_.Exception.Message)" -ForegroundColor Yellow
}

# 12. Selesai
Write-Host "`n===================================================" -ForegroundColor Green
Write-Host "[SUCCESS] Instalasi Agen Checkmk Windows Selesai!" -ForegroundColor Green
Write-Host "- Service    : CheckMkService (Port TCP 6556)"
Write-Host "- HW Monitor : $LibDir\LibreHardwareMonitorLib.dll"
Write-Host "- Inventory  : $PluginsDir\mk_inventory.vbs"
Write-Host "- Local List : $LocalDir ($($LocalChecks.Count) file)"
Write-Host "===================================================" -ForegroundColor Green

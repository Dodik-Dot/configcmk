# install.ps1 - Script Installer Otomatis Agen Checkmk untuk Windows Client
# Dijalankan via PowerShell Administrator (One-Liner Bypass)

$ErrorActionPreference = "Stop"

# 1. Pastikan script berjalan sebagai Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "Script ini HARUS dijalankan sebagai Administrator!"
    Exit
}

# 2. Konfigurasi Default & Parser Argumen Manual (Menghindari error 'param' di IEX)
$ServerIP      = "192.168.1.100"       # Default IP Server Checkmk
$SiteName      = "cmk"                 # Default Site ID Checkmk Anda
$AgentVersion  = "2.5.0p9"             # Default Versi Agen Checkmk
$GithubUser    = "andin1st"            # Username GitHub Anda
$GithubRepo    = "scriptcmk"           # Nama repositori GitHub Anda
$Branch        = "main"

# Parsing argumen manual dari $args
for ($i = 0; $i -lt $args.Count; $i++) {
    switch ($args[$i]) {
        "-s" { $ServerIP = $args[++$i] }
        "-ServerIP" { $ServerIP = $args[++$i] }
        "-d" { $SiteName = $args[++$i] }
        "-SiteName" { $SiteName = $args[++$i] }
        "-v" { $AgentVersion = $args[++$i] }
        "-AgentVersion" { $AgentVersion = $args[++$i] }
        "-g" { $GithubUser = $args[++$i] }
        "-GithubUser" { $GithubUser = $args[++$i] }
        "-r" { $GithubRepo = $args[++$i] }
        "-GithubRepo" { $GithubRepo = $args[++$i] }
        "-b" { $Branch = $args[++$i] }
        "-Branch" { $Branch = $args[++$i] }
    }
}

# 3. Pencegahan Port-Doubling (:8089:8000) & Ekstraksi Host
$CleanHost = $ServerIP -replace '^https?://', ''
$HostOnly  = ($CleanHost -split ':')[0]

# Jika ServerIP mengandung port kustom (misal untuk Web GUI), gunakan port tersebut untuk download MSI
if ($ServerIP -like "*:*") {
    $CmkServer = "http://$ServerIP"
} else {
    $CmkServer = "http://$ServerIP:8080" # Default port Web GUI
}

$BaseUrl          = "https://raw.githubusercontent.com/$GithubUser/$GithubRepo/$Branch/windows"
$MsiUrl           = "$CmkServer/$SiteName/check_mk/agents/windows/check_mk_agent.msi"

# Folder lokal tujuan
$AgentLocalFolder = "C:\ProgramData\checkmk\agent\local"
$LogFolder        = "C:\ProgramData\checkmk\agent\log_custom"
$MsiLocalPath     = "$env:TEMP\check_mk_agent.msi"
$RamScriptPath    = "C:\ProgramData\checkmk\agent\run_memtester.ps1"

Write-Host "=== Memulai Instalasi Otomatis Agen Checkmk di Windows ===" -ForegroundColor Cyan
Write-Host "Server IP  : $ServerIP" -ForegroundColor Gray
Write-Host "Host Only  : $HostOnly" -ForegroundColor Gray
Write-Host "Site Name  : $SiteName" -ForegroundColor Gray
Write-Host "Target Ver : $AgentVersion" -ForegroundColor Gray
Write-Host "MSI URL    : $MsiUrl" -ForegroundColor Gray

# 4. Buat direktori yang dibutuhkan jika belum ada
if (-not (Test-Path $AgentLocalFolder)) {
    New-Item -ItemType Directory -Force -Path $AgentLocalFolder | Out-Null
    Write-Host "[OK] Folder local checks dibuat: $AgentLocalFolder" -ForegroundColor Green
}
if (-not (Test-Path $LogFolder)) {
    New-Item -ItemType Directory -Force -Path $LogFolder | Out-Null
    Write-Host "[OK] Folder log custom dibuat: $LogFolder" -ForegroundColor Green
}

# Membersihkan file cache lama agar pemindaian ulang berjalan segar
$CacheFolder = "C:\ProgramData\checkmk\agent\cache"
if (Test-Path $CacheFolder) {
    Remove-Item (Join-Path $CacheFolder "cache_*.txt") -Force -ErrorAction SilentlyContinue
    Write-Host "[OK] File cache lama dibersihkan untuk pemindaian segar." -ForegroundColor Green
}

# 5. Pemeriksaan Status & Versi Agen Terpasang (Pencegahan Re-download & Re-install)
$ShouldInstall = $true
$InstalledVersion = $null

Write-Host "[-] Memeriksa status instalasi Agen Checkmk pada komputer host..." -ForegroundColor Yellow

# Query Registry untuk mencari program "Checkmk Agent"
$RegUninstallPaths = @(
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)
$RegAgent = Get-ItemProperty -Path $RegUninstallPaths -ErrorAction SilentlyContinue | 
            Where-Object { $_.DisplayName -match "Check(mk|_MK) Agent" } | Select-Object -First 1

if ($RegAgent) {
    $InstalledVersion = $RegAgent.DisplayVersion
    Write-Host "[INFO] Agen Checkmk terdeteksi terpasang di sistem. Versi: $InstalledVersion" -ForegroundColor Gray
} else {
    # Fallback ke file version properties secara langsung
    $agentExe = "C:\Program Files (x86)\checkmk\service\check_mk_agent.exe"
    if (-not (Test-Path $agentExe)) {
        $agentExe = "C:\Program Files\checkmk\service\check_mk_agent.exe"
    }
    if (Test-Path $agentExe) {
        $InstalledVersion = (Get-Item $agentExe).VersionInfo.ProductVersion
        Write-Host "[INFO] File Agen Checkmk ditemukan di disk. Versi: $InstalledVersion" -ForegroundColor Gray
    }
}

# Fungsi pembanding versi cerdas (contoh: "2.5.0p9" -> "2.5.0.9")
function Compare-Versions {
    param([string]$v1, [string]$v2)
    if ($v1 -eq $v2) { return 0 }
    
    $v1Norm = $v1 -replace '[a-zA-Z]', '.' -replace '\.+', '.' -replace '^\.', '' -replace '\.$', ''
    $v2Norm = $v2 -replace '[a-zA-Z]', '.' -replace '\.+', '.' -replace '^\.', '' -replace '\.$', ''
    
    try {
        $version1 = [System.Version]$v1Norm
        $version2 = [System.Version]$v2Norm
        return $version1.CompareTo($version2)
    } catch {
        return [string]::Compare($v1, $v2, $true)
    }
}

if ($InstalledVersion) {
    $Comparison = Compare-Versions -v1 $InstalledVersion -v2 $AgentVersion
    if ($Comparison -ge 0) {
        $ShouldInstall = $false
        Write-Host "[OK] Versi terpasang ($InstalledVersion) sudah sesuai atau lebih baru dibanding versi server ($AgentVersion)." -ForegroundColor Green
        Write-Host "[INFO] Melewati pengunduhan dan pemasangan ulang file MSI agen." -ForegroundColor Green
    } else {
        Write-Host "[WARNING] Versi terpasang ($InstalledVersion) lebih usang dibanding versi target server ($AgentVersion)." -ForegroundColor Yellow
        Write-Host "[-] Mempersiapkan proses pembaruan (upgrade) ke versi $AgentVersion..." -ForegroundColor Yellow
    }
} else {
    Write-Host "[INFO] Agen Checkmk belum terpasang di komputer host target." -ForegroundColor Gray
    Write-Host "[-] Memulai instalasi baru versi $AgentVersion..." -ForegroundColor Yellow
}

# 6. Unduh dan Pemasangan Agen Checkmk secara Silent (Hanya jika dibutuhkan)
if ($ShouldInstall) {
    Write-Host "[-] Mengunduh installer Agen Checkmk dari server..." -ForegroundColor Yellow
    try {
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
        Invoke-WebRequest -Uri $MsiUrl -OutFile $MsiLocalPath -UseBasicParsing
        Write-Host "[OK] Berhasil mengunduh installer agen." -ForegroundColor Green

        Write-Host "[-] Menginstal/Memperbarui Agen Checkmk secara silent (tanpa GUI)..." -ForegroundColor Yellow
        $installProcess = Start-Process msiexec.exe -ArgumentList "/i `"$MsiLocalPath`" /qn /norestart" -Wait -PassThru
        if ($installProcess.ExitCode -eq 0 -or $installProcess.ExitCode -eq 3010) {
            Write-Host "[OK] Agen Checkmk berhasil diinstal!" -ForegroundColor Green
        } else {
            Write-Warning "Instalasi agen selesai dengan ExitCode: $($installProcess.ExitCode)"
        }
    } catch {
        Write-Error "Gagal mengunduh atau menginstal agen Checkmk: $_"
    } finally {
        if (Test-Path $MsiLocalPath) { Remove-Item $MsiLocalPath -Force }
    }
}

# 7. Unduh Script Local Checks dari GitHub (Tepat 10 Skrip)
$LocalChecks = @(
    "battery_health.ps1",
    "cpu_info.ps1",
    "disk_nvme_health.ps1",
    "fan_health.ps1",
    "info_network.ps1",
    "info_OS_office.ps1",
    "ram_health.ps1",
    "ram_usage.ps1",
    "remote_apps.ps1",
    "storage_usage.ps1"
)

Write-Host "[-] Mengunduh 10 script Local Checks dari GitHub..." -ForegroundColor Yellow
foreach ($script in $LocalChecks) {
    $scriptUrl = "$BaseUrl/local_checks/$script"
    $destination = Join-Path $AgentLocalFolder $script
    try {
        Invoke-WebRequest -Uri $scriptUrl -OutFile $destination -UseBasicParsing
        Write-Host " -> [OK] Mengunduh $script" -ForegroundColor Green
    } catch {
        Write-Warning "Gagal mengunduh script: $script dari $scriptUrl. Melewati..."
    }
}

# 8. Setup RAM Health (Pengujian Memtester / Memory Diagnostik Asinkron - Setiap Sabtu 11:00)
Write-Host "[-] Menyiapkan penjadwalan uji kesehatan RAM (Setiap Sabtu 11:00 AM)..." -ForegroundColor Yellow

# Script internal Windows untuk simulasi pengujian memtester asinkron
$RamCheckScriptContent = @'
# Script Windows RAM Test (Sebagai representasi memtester di Windows)
$LogFile = "C:\ProgramData\checkmk\agent\log_custom\memtester_health.log"
$Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

Add-Content -Path $LogFile -Value "=== MEMTESTER START: $Timestamp ==="

# Menjalankan stress memory sederhana menggunakan alokasi objek .NET
try {
    Write-Output "Mengalokasikan memori untuk testing..."
    $testArray = New-Object Byte[] (256 * 1024 * 1024) # 256MB
    for ($i = 0; $i -lt $testArray.Length; $i += 4096) {
        $testArray[$i] = 1
    }
    # Kosongkan memory kembali
    $testArray = $null
    [System.GC]::Collect()
    
    # Query logs hardware ECC memory jika didukung perangkat (WMI)
    $memoryErrors = Get-CimInstance -ClassName Win32_MemoryDevice | Where-Object { $_.ErrorCorrecting -eq $true -and $_.ErrorDescription -ne $null }
    
    if ($memoryErrors) {
        Add-Content -Path $LogFile -Value "STATUS: FAILED"
        Add-Content -Path $LogFile -Value "Error details: Terdeteksi kesalahan hardware pada modul RAM."
    } else {
        Add-Content -Path $LogFile -Value "STATUS: SUCCESS"
        Add-Content -Path $LogFile -Value "Memory allocation and system diagnostics passed."
    }
} catch {
    Add-Content -Path $LogFile -Value "STATUS: FAILED"
    Add-Content -Path $LogFile -Value "Error during diagnostic run: $_"
}

$EndTimestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Add-Content -Path $LogFile -Value "=== MEMTESTER END: $EndTimestamp ==="
'@

# Simpan script pengujian RAM asinkron ke sistem
$RamCheckScriptContent | Out-File -FilePath $RamScriptPath -Encoding utf8 -Force

# Registrasikan Task Scheduler untuk berjalan setiap hari Sabtu pukul 11:00 Pagi
$TaskName = "Checkmk_RAM_Health_Test"
$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File '$RamScriptPath'"
$Trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Saturday -At 11am
$Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount

# Hapus task lama jika sudah ada agar ter-update
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false | Out-Null
}

try {
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Principal $Principal | Out-Null
    Write-Host "[OK] Windows Task Scheduler '$TaskName' berhasil didaftarkan!" -ForegroundColor Green
    
    # Jalankan tes pertama kali di background agar file log langsung terbuat
    Start-ScheduledTask -TaskName $TaskName
    Write-Host "[OK] Menjalankan pengujian RAM inisial pertama kali..." -ForegroundColor Green
} catch {
    Write-Warning "Gagal mendaftarkan Scheduled Task untuk pengujian RAM: $_"
}

# 9. Deteksi Lokasi cmk-agent-ctl.exe untuk Membantu Registrasi yang Akurat
$ctlPath = "C:\Program Files (x86)\checkmk\service\cmk-agent-ctl.exe"
if (-not (Test-Path $ctlPath)) {
    $ctlPath = "C:\Program Files\checkmk\service\cmk-agent-ctl.exe"
}

Write-Host "=== Proses Instalasi Selesai! Agen Anda Siap Digunakan ===" -ForegroundColor Green
Write-Host "Untuk mendaftarkan sertifikat agen ke server Checkmk, jalankan perintah berikut sebagai Administrator:" -ForegroundColor Green
Write-Host " & `"$ctlPath`" register --hostname <NAMA_HOST> --server ${HostOnly}:8000 --site $SiteName --user cmkadmin" -ForegroundColor Yellow

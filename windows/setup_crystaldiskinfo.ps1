# ==========================================================
# setup_crystaldiskinfo.ps1
# Repositori: Dodik-Dot/configcmk
# Menyiapkan Scheduled Task CrystalDiskInfo tiap 6 jam
# ==========================================================
param(
    [string]$CdiPath = '',
    [switch]$AsCurrentUser
)

$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin  = ([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host '[!] Script ini HARUS dijalankan sebagai Administrator!' -ForegroundColor Red
    exit 1
}

$AgentRoot = 'C:\ProgramData\checkmk\agent'$LogFolder = Join-Path $AgentRoot 'log_custom'$ToolsDir  = Join-Path $AgentRoot 'tools\CrystalDiskInfo'$Wrapper   = Join-Path $AgentRoot 'run_crystaldiskinfo.ps1'$OutFile   = Join-Path $LogFolder 'diskinfo.txt'$TaskName  = 'Checkmk_CrystalDiskInfo'

foreach ($d in @($LogFolder,$ToolsDir)) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Force -Path$d | Out-Null }
}

function Find-Cdi {
    $candidates = @(
        'C:\Program Files\CrystalDiskInfo\DiskInfo64.exe',
        'C:\Program Files (x86)\CrystalDiskInfo\DiskInfo64.exe',
        'C:\CrystalDiskInfo\DiskInfo64.exe',
        (Join-Path $ToolsDir 'DiskInfo64.exe')
    )
    $running = Get-Process DiskInfo64 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($running -and $running.Path) {$candidates = @($running.Path) +$candidates }
    foreach ($c in$candidates) {
        if (Test-Path $c) { return$c }
    }
    return ''
}

if (-not $CdiPath) {$CdiPath = Find-Cdi }

# 1. Coba pasang lewat winget jika belum ada
if (-not $CdiPath -or -not (Test-Path $CdiPath)) {$winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($winget) {
        Write-Host '[-] CrystalDiskInfo belum ada, mencoba memasang lewat winget...' -ForegroundColor Yellow
        try {
            & $winget.Source install --id CrystalDewWorld.CrystalDiskInfo -e --silent --accept-package-agreements --accept-source-agreements | Out-Host
        } catch {}
        $CdiPath = Find-Cdi
    }
}

# 2. Fallback: Unduh portable ZIP dari repo Dodik-Dot/configcmk jika winget gagal
if (-not $CdiPath -or -not (Test-Path $CdiPath)) {$zipUrl  = 'https://raw.githubusercontent.com/Dodik-Dot/configcmk/main/windows/tools/CrystalDiskInfo.zip'
    $zipPath = "$env:TEMP\cdi_portable.zip"
    Write-Host '[-] Mencoba mengunduh CrystalDiskInfo Portable dari GitHub...' -ForegroundColor Yellow
    try {
        & curl.exe -s -k -L --max-time 60 "$zipUrl" -o "$zipPath"
        if ((Test-Path $zipPath) -and ((Get-Item$zipPath).Length -gt 100KB)) {
            Expand-Archive -Path $zipPath -DestinationPath$ToolsDir -Force
            Remove-Item $zipPath -Force -ErrorAction SilentlyContinue$CdiPath = Find-Cdi
        }
    } catch {}
}

if (-not $CdiPath -or -not (Test-Path$CdiPath)) {
    Write-Host '[!] DiskInfo64.exe tidak ditemukan. Lewati setup CrystalDiskInfo.' -ForegroundColor Yellow
    exit 0
}
Write-Host "[OK] CrystalDiskInfo: $CdiPath" -ForegroundColor Green

# Pastikan DiskInfo.ini ada agar akun SYSTEM tidak tertahan inisialisasi pertama
$cdiDir = Split-Path$CdiPath
$iniFile = Join-Path$cdiDir 'DiskInfo.ini'
if (-not (Test-Path $iniFile)) {
    "[Setting]`r`nLanguage=English`r`n" | Set-Content -Path $iniFile -Encoding ASCII -Force
}

# ---------- Buat script pembungkus ----------
$template = @'$ErrorActionPreference = 'SilentlyContinue'
$cdi = '__CDI__'$out = '__OUT__'
$dir = Split-Path$cdi
$txt = Join-Path$dir 'DiskInfo.txt'
if (Test-Path $txt) { Remove-Item $txt -Force }$p = Start-Process -FilePath $cdi -ArgumentList '/CopyExit' -WorkingDirectory$dir -WindowStyle Hidden -PassThru
if ($p) {
    if (-not $p.WaitForExit(45000)) { Stop-Process -Id$p.Id -Force }
}
if (Test-Path $txt) {
    Copy-Item $txt$out -Force
    Remove-Item "$env:ProgramData\checkmk\agent\cache\cache_disk_health.txt" -Force -ErrorAction SilentlyContinue
}
'@
$content =$template.Replace('__CDI__', $CdiPath).Replace('__OUT__',$OutFile)
Set-Content -Path $Wrapper -Value$content -Encoding ASCII -Force
Write-Host "[OK] Script pembungkus dibuat: $Wrapper" -ForegroundColor Green

# ---------- Daftarkan Scheduled Task (tiap 6 jam) ----------
function Register-CdiTask {
    param([bool]$AsUser)

    $Action   = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Wrapper`""
    $Trigger  = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Hours 6) -RepetitionDuration (New-TimeSpan -Days 1825)$Settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

    if ($AsUser) {
        $me =$identity.Name
        $Principal = New-ScheduledTaskPrincipal -UserId$me -LogonType Interactive -RunLevel Highest
        Write-Host "[INFO] Task berjalan sebagai $me." -ForegroundColor Cyan
    } else {
        $Principal = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' -LogonType ServiceAccount -RunLevel Highest
        Write-Host '[INFO] Task berjalan sebagai SYSTEM.' -ForegroundColor Cyan
    }

    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false | Out-Null
    }
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger$Trigger -Settings $Settings -Principal$Principal | Out-Null
}

function Test-CdiRun {
    $startTime = Get-Date
    Start-ScheduledTask -TaskName $TaskName
    Write-Host '[-] Menjalankan CrystalDiskInfo, menunggu hasil (maks 45 detik)...' -ForegroundColor Yellow
    for ($i = 0; $i -lt 23; $i++) {
        if ((Test-Path $OutFile) -and ((Get-Item$OutFile).LastWriteTime -gt $startTime)) { return$true }
        Start-Sleep -Seconds 2
    }
    return $false
}

$modes = if ($AsCurrentUser) { @($true) } elseif ($identity.IsSystem) { @($false) } else { @($false,$true) }

$ok =$false
foreach ($m in$modes) {
    Register-CdiTask -AsUser $m
    if (Test-CdiRun) { $ok =$true; break }
    Write-Host '[!] File diskinfo.txt belum terbentuk dengan mode ini, mencoba mode cadangan...' -ForegroundColor Yellow
}

if ($ok) {
    Write-Host "[OK] Berhasil membentuk: $OutFile" -ForegroundColor Green
} else {
    Write-Host '[!] File diskinfo.txt belum terbentuk, fallback Windows API tetap aktif.' -ForegroundColor Yellow
}

# ==========================================================
# update_checks.ps1 - Auto-update script Checkmk dari GitHub
# Repositori: Dodik-Dot/configcmk
# Dijalankan oleh Scheduled Task "Checkmk_Auto_Update" (SYSTEM)
# ==========================================================
param(
    [string]$GithubUser = 'Dodik-Dot',
    [string]$GithubRepo = 'configcmk',
    [string]$Branch     = 'main'
)

$ErrorActionPreference = 'Stop'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13 } catch {}

$BaseUrl   = "https://raw.githubusercontent.com/$GithubUser/$GithubRepo/$Branch/windows"
$AgentRoot = 'C:\ProgramData\checkmk\agent'
$LocalDir  = Join-Path $AgentRoot 'local'
$PluginDir = Join-Path $AgentRoot 'plugins'
$CacheDir  = Join-Path $AgentRoot 'cache'
$LogDir    = Join-Path $AgentRoot 'log_custom'
$LogFile   = Join-Path $LogDir 'update_checks.log'
$TempDir   = Join-Path $env:TEMP 'checkmk_update'

# Daftar bawaan sesuai struktur repo Dodik-Dot/configcmk
$DefaultLocalList = @(
    'battery_health.ps1', 'cpu_info.ps1', 'disk_nvme_health.ps1', 'fan_health.ps1',
    'info_network.ps1', 'info_OS_office.ps1', 'ram_health.ps1', 'ram_usage.ps1',
    'remote_access_id.ps1', 'remote_apps.ps1', 'storage_usage.ps1'
)

foreach ($d in @($LogDir, $LocalDir, $PluginDir, $CacheDir, $TempDir)) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
}

function Write-Log {
    param([string]$Msg)
    $line = '{0}  {1}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $Msg
    try {
        if ((Test-Path $LogFile) -and ((Get-Item $LogFile).Length -gt 200KB)) {
            Get-Content $LogFile -Tail 200 | Set-Content $LogFile -Encoding UTF8
        }
        Add-Content -Path $LogFile -Value $line -Encoding UTF8
    } catch {}
}

function Download-FileSafe {
    param([string]$Url, [string]$OutFile)
    $cacheBustUrl = "$Url?v=$((Get-Date).Ticks)"
    if (Test-Path $OutFile) { Remove-Item $OutFile -Force -ErrorAction SilentlyContinue }
    
    # Utama: curl.exe (Bebas bug TLS PowerShell 5.1)
    & curl.exe -s -k -L --max-time 30 "$cacheBustUrl" -o "$OutFile" 2>$null
    
    # Fallback: Invoke-WebRequest jika curl gagal
    if (-not (Test-Path $OutFile) -or (Get-Item $OutFile).Length -eq 0) {
        Invoke-WebRequest -Uri $cacheBustUrl -OutFile $OutFile -UseBasicParsing -TimeoutSec 30
    }
}

function Sync-File {
    param([string]$Url, [string]$Dest)
    $tmp = Join-Path $TempDir ([IO.Path]::GetFileName($Dest) + '.new')
    Download-FileSafe -Url $Url -OutFile $tmp
    if (-not (Test-Path $tmp) -or (Get-Item $tmp).Length -eq 0) { throw 'file kosong atau gagal diunduh' }

    $same = $false
    if (Test-Path $Dest) {
        $same = ((Get-FileHash $tmp -Algorithm SHA256).Hash -eq (Get-FileHash $Dest -Algorithm SHA256).Hash)
    }
    if ($same) { Remove-Item $tmp -Force; return 'same' }

    Copy-Item $tmp $Dest -Force
    Unblock-File -Path $Dest -ErrorAction SilentlyContinue
    Remove-Item $tmp -Force
    return 'updated'
}

# ---------- 1. Ambil Daftar File ----------
$files = @($DefaultLocalList)
try {
    $manifestTmp = Join-Path $TempDir 'manifest.txt'
    Download-FileSafe -Url "$BaseUrl/local_checks/manifest.txt" -OutFile $manifestTmp
    if ((Test-Path $manifestTmp) -and ((Get-Item $manifestTmp).Length -gt 0)) {
        $fromManifest = @(Get-Content $manifestTmp | ForEach-Object { $_.Trim() } |
            Where-Object { $_ -and -not $_.StartsWith('#') -and $_ -match '^[A-Za-z0-9_.\-]+\.ps1$' })
        if ($fromManifest.Count -gt 0) { $files = $fromManifest }
    }
    Remove-Item $manifestTmp -Force -ErrorAction SilentlyContinue
} catch {}

# ---------- 2. Sinkronkan Local Checks ----------
$updated = 0
$failed  = 0
foreach ($f in $files) {
    $dest = Join-Path $LocalDir $f
    try {
        $r = Sync-File -Url "$BaseUrl/local_checks/$f" -Dest $dest
        if ($r -eq 'updated') {
            $updated++
            Write-Log "DIPERBARUI: $f"
        }
    } catch {
        $failed++
        Write-Log "GAGAL: $f ($($_.Exception.Message))"
    }
}

# Jika ada script yang diperbarui, bersihkan cache agar hasil baru langsung tampil di Checkmk
if ($updated -gt 0) {
    Remove-Item "$CacheDir\cache_*.txt" -Force -ErrorAction SilentlyContinue
    Write-Log "Cache dibersihkan karena ada $updated script yang diperbarui."
}

Write-Log "Selesai. diperbarui=$updated gagal=$failed total=$($files.Count)"

# ---------- 3. Perbarui diri sendiri ----------
try {
    if ($PSCommandPath) {
        $r = Sync-File -Url "$BaseUrl/update_checks.ps1" -Dest $PSCommandPath
        if ($r -eq 'updated') { Write-Log 'update_checks.ps1 sendiri diperbarui.' }
    }
} catch {}

# Setup CrystalDiskInfo Scheduled Task (Checkmk)
$ErrorActionPreference = 'SilentlyContinue'
$root = 'C:\ProgramData\checkmk\agent'
$logDir = Join-Path $root 'log_custom'
$toolsDir = Join-Path $root 'tools\CrystalDiskInfo'
$runner = Join-Path $root 'run_crystaldiskinfo.ps1'
$outTxt = Join-Path $logDir 'diskinfo.txt'
$taskName = 'Checkmk_CrystalDiskInfo'

New-Item -ItemType Directory -Force -Path $logDir, $toolsDir | Out-Null

$cdiExe = @(
    'C:\Program Files\CrystalDiskInfo\DiskInfo64.exe',
    'C:\Program Files (x86)\CrystalDiskInfo\DiskInfo64.exe',
    'C:\CrystalDiskInfo\DiskInfo64.exe',
    (Join-Path $toolsDir 'DiskInfo64.exe')
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $cdiExe) {
    $wg = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($wg) {
        & $wg.Source install --id CrystalDewWorld.CrystalDiskInfo -e --silent --accept-package-agreements --accept-source-agreements | Out-Null
    }
    $cdiExe = @(
        'C:\Program Files\CrystalDiskInfo\DiskInfo64.exe',
        'C:\Program Files (x86)\CrystalDiskInfo\DiskInfo64.exe'
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
}

if (-not $cdiExe) {
    $zip = Join-Path $toolsDir 'cdi.zip'
    & curl.exe -s -k -L --max-time 60 'https://raw.githubusercontent.com/Dodik-Dot/configcmk/main/windows/tools/CrystalDiskInfo.zip' -o $zip
    if ((Test-Path $zip) -and ((Get-Item $zip).Length -gt 100KB)) {
        Expand-Archive -Path $zip -DestinationPath $toolsDir -Force
        Remove-Item $zip -Force
    }
    $cdiExe = Get-ChildItem -Path $toolsDir -Filter 'DiskInfo64.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
}

if (-not $cdiExe) {
    Write-Host '[!] DiskInfo64.exe belum ditemukan, melewati setup CrystalDiskInfo.' -ForegroundColor Yellow
    exit 0
}

$cdiFolder = Split-Path $cdiExe
$iniPath = Join-Path $cdiFolder 'DiskInfo.ini'
if (-not (Test-Path $iniPath)) {
    Set-Content -Path $iniPath -Value "[Setting]`r`nLanguage=English`r`n" -Encoding ASCII -Force
}

$lines = @(
    "`$ErrorActionPreference = 'SilentlyContinue'",
    "`$exe = '$cdiExe'",
    "`$dir = Split-Path `$exe",
    "`$src = Join-Path `$dir 'DiskInfo.txt'",
    "if (Test-Path `$src) { Remove-Item `$src -Force }",
    "`$proc = Start-Process -FilePath `$exe -ArgumentList '/CopyExit' -WorkingDirectory `$dir -WindowStyle Hidden -PassThru",
    "if (`$proc -and -not `$proc.WaitForExit(45000)) { Stop-Process -Id `$proc.Id -Force }",
    "if (Test-Path `$src) { Copy-Item `$src '$outTxt' -Force }"
)
Set-Content -Path $runner -Value ($lines -join "`r`n") -Encoding ASCII -Force

$act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$runner`""
$trg = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Hours 6) -RepetitionDuration (New-TimeSpan -Days 1825)
$cfg = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
$usr = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' -LogonType ServiceAccount -RunLevel Highest

Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
Register-ScheduledTask -TaskName $taskName -Action $act -Trigger $trg -Settings $cfg -Principal $usr | Out-Null
Start-ScheduledTask -TaskName $taskName
Write-Host "[OK] Scheduled Task $taskName berhasil dibuat dan dijalankan." -ForegroundColor Green

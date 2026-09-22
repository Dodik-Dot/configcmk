$ErrorActionPreference = 'SilentlyContinue'

$Smartctl = "C:\Program Files\smartmontools\bin\smartctl.exe"
if (-not (Test-Path $Smartctl)) {
    $Smartctl = "C:\Program Files (x86)\smartmontools\bin\smartctl.exe"
}

if (-not (Test-Path $Smartctl)) {
    Write-Output "1 `"Storage_Health`" - WARN: smartctl.exe tidak ditemukan"
    exit
}

$pipe = " " + [char]124 + " "
$scanLines = & $Smartctl --scan | Where-Object { $_ -match '^/dev/sd[a-z]' }

foreach ($line in $scanLines) {
    if ($line -match '^(/dev/sd[a-z])\s+-d\s+(\S+)') {
        $devPath = $matches[1]
        $devType = $matches[2]

        $rawOutput = & $Smartctl -i -H -A -d $devType $devPath 2>$null
        $text = $rawOutput -join "`n"

        $Model = "Unknown Storage"
        if ($text -match '(?mi)^Model Number:\s*(.+)$') {
            $Model =$matches[1].Trim()
        } elseif ($text -match '(?mi)^Device Model:\s*(.+)$') {
            $Model =$matches[1].Trim()
        }

        $IsNVMe = ($devType -eq "nvme") -or ($text -match "NVMe")
        $DriveType = "HDD (Mekanik)"
        if ($IsNVMe) {$DriveType = "NVME"
        } elseif ($text -match "Solid State|SSD") {
            $DriveType = "SSD Sata"
        }

        $Suhu = "N/A"
        if ($text -match '(?mi)^Temperature:\s*(\d+)\s*Celsius') {$Suhu = "$($matches[1]) Celcius"
        } elseif ($text -match '(?mi)^\s*(?:194\vert{}190)\s+Temperature[^\d]+(\d+)') {$Suhu = "$($matches[1]) Celcius"
        }

        $SmartStatus = "UNKNOWN"
        if ($text -match '(?mi)SMART overall-health self-assessment test result:\s*([^\r\n]+)') {
            $SmartStatus =$matches[1].Trim()
        } elseif ($text -match '(?mi)SMART Health Status:\s*([^\r\n]+)') {
            $SmartStatus =$matches[1].Trim()
        } elseif ($IsNVMe -and ($text -match 'Percentage Used')) {$SmartStatus = "PASSED"
        }

        $Health = "100%"
        $DetailInfo = ""
        $State = 0

        if ($IsNVMe) {
            if ($text -match '(?mi)^Percentage Used:\s*(\d+)%') {
                $Used = [int]$matches[1]
                $HealthVal = 100 -$Used
                if ($HealthVal -lt 0) {$HealthVal = 0 }
                $Health = "$HealthVal%"
                if ($HealthVal -le 10) {$State = 2 }
                elseif ($HealthVal -le 30) {$State = 1 }
            }
            if ($text -match '(?mi)^Data Units Written:\s*[\d,]+\s*\[([^\]]+)\]') {
                $DetailInfo = "TBW: " + $matches[1].Trim() +$pipe
            }
        } else {
            $BadSector = 0
            if ($text -match '(?mi)^\s*5\s+Reallocated_Sector_Ct[^\d]+(\d+)') {
                $BadSector = [int]$matches[1]
            }
            if ($BadSector -gt 0) {
                $Health = "Perhatian ($BadSector Bad Sector)"
                $State = 1             } else {$Health = "Sehat (0 Bad Sector)"
            }
            if ($text -match '(?mi)^\s*9\s+Power_On_Hours[^\d]+(\d+)') {$Hours = [int]$matches[1]$Days = [math]::Round($Hours / 24, 0)$DetailInfo = "Total Dipakai: $Hours Jam ($Days Hari)" + $pipe
            }
        }

        if ($SmartStatus -notmatch 'PASSED\vert{}OK') {$State = 2
        }

        $CleanName = ($Model -replace '[^a-zA-Z0-9_\-]', '_').Trim('_')
        if (-not $CleanName) {
            $CleanName = ($devPath -replace '\W', '_')
        }

        $ServiceName = "Storage_Health_" + $CleanName
        $Summary = "Status : OK" + $pipe + "Drive: " + $DriveType +$pipe + "Merk: " + $Model +$pipe + "Kesehatan: " + $Health +$pipe + "Suhu: " + $Suhu +$pipe + $DetailInfo + "SMART: " + $SmartStatus

        Write-Output "$State `"$ServiceName`" - $Summary"
    }
}

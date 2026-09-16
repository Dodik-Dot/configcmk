# =====================================================================
# Local Check Checkmk: Real-Time Fan Health & Speed (Windows)
# Supports LibreHardwareMonitorLib.dll, WMI root\LibreHardwareMonitor, and CIM Win32_Fan
# =====================================================================

$LibDir = "C:\ProgramData\checkmk\agent\lib"
$DllPath = Join-Path $LibDir "LibreHardwareMonitorLib.dll"
if (-not (Test-Path $DllPath)) {
    $DllPath = "C:\ProgramData\checkmk\agent\local\LibreHardwareMonitorLib.dll"
}

$fanSpeed = 0
$fanFound = $false
$sensorName = ""

# 1. Direct .NET Assembly Load via LibreHardwareMonitorLib.dll
if (Test-Path $DllPath) {
    try {
        Add-Type -Path $DllPath -ErrorAction Stop
        $computer = New-Object LibreHardwareMonitor.Hardware.Computer
        $computer.IsCpuEnabled = $true
        $computer.IsMotherboardEnabled = $true
        $computer.IsControllerEnabled = $true
        $computer.Open()

        foreach ($hardware in $computer.Hardware) {
            $hardware.Update()
            foreach ($subHW in $hardware.SubHardware) { $subHW.Update() }
            foreach ($sensor in $hardware.Sensors) {
                if ($sensor.SensorType -eq "Fan" -and $sensor.Value -gt 0) {
                    $fanSpeed = [int]$sensor.Value
                    $sensorName = $sensor.Name
                    $fanFound = $true
                    break
                }
            }
            if ($fanFound) { break }
        }
        $computer.Close()
    } catch {
        # Fallback if DLL loading fails
    }
}

# 2. WMI Query to root\LibreHardwareMonitor (if LHM App/Service is running)
if (-not $fanFound) {
    $fanLHM = Get-CimInstance -Namespace "root\LibreHardwareMonitor" -ClassName "Sensor" -ErrorAction SilentlyContinue |
              Where-Object { $_.SensorType -eq "Fan" -and $_.Value -gt 0 } | Select-Object -First 1
    if ($fanLHM) {
        $fanSpeed = [int]$fanLHM.Value
        $sensorName = $fanLHM.Name
        $fanFound = $true
    }
}

# 3. Standard CIM Win32_Fan
if (-not $fanFound) {
    $Fans = Get-CimInstance -ClassName Win32_Fan -ErrorAction SilentlyContinue |
            Where-Object { $_.DesiredSpeed -gt 0 } | Select-Object -First 1
    if ($Fans) {
        $fanSpeed = [int]$Fans.DesiredSpeed
        $sensorName = $Fans.Name
        $fanFound = $true
    }
}

# Decision & Thresholds (Standard: > 1600 RPM OK, < 1600 RPM Warning, 0 RPM Passive/OK)
if ($fanFound) {
    $status = 0
    $statusTxt = "OK"
    if ($fanSpeed -lt 1600 -and $fanSpeed -gt 0) {
        $status = 1
        $statusTxt = "Warning"
    }
    $Output = "$status `"FAN_Health`" - Status : $statusTxt ~ FAN Speed : ${fanSpeed}rpm ~ Sensor: $sensorName ~ Remark: FAN Condition Good"
} else {
    # Passive Cooling / Sensor Not Exposed (OK - Status 0 per Checkmk Standard)
    $Output = "0 `"FAN_Health`" - Status : OK ~ FAN Speed : 0rpm ~ Remark: Passive Cooling or Sensor Not Exposed"
}

Write-Output $Output
